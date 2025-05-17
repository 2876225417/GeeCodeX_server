#ifndef HTTP_IMPL_HPP
#define HTTP_IMPL_HPP

#include "database/db_conn.h"
#include "database/db_ops.hpp"
#include "http/router.hpp"
#include <algorithm>
#include <boost/asio/ssl/context.hpp>
#include <boost/asio/ssl/verify_mode.hpp>
#include <boost/beast/core/error.hpp>
#include <boost/beast/core/file_base.hpp>
#include <boost/beast/http/field.hpp>
#include <boost/beast/http/file_body_fwd.hpp>
#include <boost/beast/http/message_fwd.hpp>
#include <boost/beast/http/status.hpp>
#include <boost/beast/http/string_body_fwd.hpp>
#include <boost/utility/string_view_fwd.hpp>
#include <boost/algorithm/string/trim.hpp>
#include <boost/asio/ssl/error.hpp>
#include <boost/asio/ssl/context.hpp>
#include <boost/asio/ssl/stream.hpp>
#include <cstdlib>
#include <exception>
#include <iterator>
#include <json.hpp>
#include <memory>
#include <mutex>
#include <optional>
#include <ostream>
#include <pqxx/pqxx>
#include <http/http_connection.h>
#include <filesystem>
#include <boost/beast/http/file_body.hpp>
#include <regex>
#include <stdexcept>
#include <string>
#include <utility>
#include <boost/algorithm/string/case_conv.hpp>
#include <charconv>
#include <boost/algorithm/string/split.hpp>
#include <boost/algorithm/string/classification.hpp>
#include <boost/algorithm/string/predicate.hpp>


namespace geecodex::http {
namespace net = boost::asio;
namespace ssl = net::ssl;
using tcp = net::ip::tcp;

inline void handle_hello(http_connection& conn) { 
    auto& m_response = conn.response();
    m_response.set(http::field::content_type, "text/plain");
    m_response.body() = "Hello C++";
}    
    
inline void handle_health_check(http_connection& conn) {
    auto& m_response = conn.response();
    try {
        bool database_connected = false;
        try {
            pqxx::result result = execute_query("SELECT 1");
            database_connected = !result.empty();
        } catch (const std::exception& e) {
            database_connected = false;
        }
    
        nlohmann::json response_json;
        response_json["status"] = "ok";
        response_json["timestamp"] = std::time(nullptr);
        response_json["service"] = "rtsp-monitor-server";
        response_json["database_connected"] = database_connected;
    
        m_response.result(http::status::ok);
        m_response.set(http::field::content_type, "application/json");
        m_response.body() = response_json.dump();
    
        std::cout << "Health check request processed" << std::endl;
    } catch (const std::exception& e) {
        nlohmann::json error_json;
        error_json["status"] = "error";
        error_json["error"] = "Error processing health check: " + std::string(e.what());
                
        m_response.result(http::status::internal_server_error);
        m_response.set(http::field::content_type, "application/json");
        m_response.body() = error_json.dump();
    
        std::cerr << "Error during health check: " << e.what();
    }
}

inline void handle_not_found(http_connection& conn) { 
   try {
        std::cout << "Handling not found route" << std::endl;
        auto& request = conn.request();
        http::response<http::string_body> response{http::status::not_found, request.version()};
        response.set(http::field::content_type, "application/json");
        response.body() = R"({"error": "Endpoint not found"})"; 
        conn.send(std::move(response));
    } catch (const std::exception& e) {
        std::cerr << "Exception in handle_not_found: "<< e.what() << std::endl; 
        try {
            auto& request = conn.request();
            http::response<http::string_body> response{http::status::internal_server_error, request.version()};
            response.set(http::field::content_type, "application/json");
            response.body() = R"({"error": "Internal server error"})";
            conn.send(std::move(response));
        } catch (...) {
            std::cerr << "Failed to send response in handle_not_found" << std::endl;
        }
    } catch (...) {
        std::cerr << "Unknown exception in handle_not_found" << std::endl;
    }
}


namespace fs = std::filesystem;
using json = nlohmann::json;

inline void handle_download_pdf(http_connection& conn) {
    try {
        std::cout << "Handling PDF downloading request" << std::endl;
        auto& request = conn.request();

        std::string target = std::string(request.target());
        std::cout << "Target path: " << target << std::endl;

        std::regex id_pattern("/geecodex/books/(\\d+)(?:/pdf)?");
        std::smatch matches;

        if (!std::regex_search(target, matches, id_pattern) || matches.size() < 2) {
            std::cout << "Invalid path format: " << target << std::endl;
            http::response<http::string_body> response{http::status::bad_request, request.version()};
            response.set(http::field::content_type, "application/json");
            response.body() = R"({"error": "Invalid book ID format"})";
            response.prepare_payload();
            conn.send(std::move(response));
            return;
        }

        int book_id = std::stoi(matches[1]);
        std::cout << "Book ID: " << book_id << std::endl;
 
        try {
            pqxx::result result = execute_params(
                "SELECT title, pdf_path, file_size_bytes, is_active, access_level "
                "FROM codex_books WHERE id = $1",
                book_id
            );
            
            if (result.empty()) {
                std::cout << "Book not found: ID " << book_id << std::endl;
                http::response<http::string_body> response{http::status::not_found, request.version()};
                response.set(http::field::content_type, "application/json");
                response.body() = R"({"error": "Book not found"})";
                conn.send(std::move(static_cast<http::response<http::string_body>&&>(response)));
                return;
            }

            const auto& row = result[0];
            std::string title = row["title"].as<std::string>();
            std::string pdf_path = row["pdf_path"].as<std::string>();
            bool is_active = row["is_active"].as<bool>();
            int access_level = row["access_level"].as<int>();

            std::cout << "Found book: " << title << ", Path: " << pdf_path << std::endl;
        
            if (!is_active) {
                http::response<http::string_body> response{http::status::forbidden, request.version()};
                response.set(http::field::content_type, "application/json");
                response.body() = R"({"error": "This book is currently unavailable"})";
                conn.send(std::move(response));
                return;
            }

            /* Access Level */
            
            fs::path file_path(pdf_path);
            if (!fs::exists(file_path) || !fs::is_regular_file(file_path)) {
                std::cerr << "PDF file not found not server: " << pdf_path << std::endl;
                http::response<http::string_body> response{http::status::not_found, request.version()};
                response.set(http::field::content_type, "application/json");
                response.body() = R"({"error": "PDF file not found on server"})";
                conn.send(std::move(response));
                return;
            }

            std::string safe_filename = title;
            safe_filename = std::regex_replace(safe_filename, std::regex("[^a-zA-Z0-9_\\- ]"), "");

            safe_filename = std::regex_replace(safe_filename, std::regex("\\s+"), "_");
            safe_filename += ".pdf";

            std::cout << "Sending file: " << safe_filename << std::endl;
           
            try {
                execute_params(
                    "UPDATE codex_books SET download_count = download_count + 1 WHERE id = $1",
                    book_id);
            } catch (const std::exception& e) {
                std::cerr << "Failed to update download count: " << e.what() << std::endl;
            }

            beast::error_code ec;
            http::file_body::value_type file;
            file.open(file_path.string().c_str(), beast::file_mode::read, ec);
    
            if (ec) {
                std::cerr << "Error opening file: " << ec.message() << std::endl;
                http::response<http::string_body> response{http::status::internal_server_error, request.version()};
                response.set(http::field::content_type, "application/json");
                response.body() = R"({"error": "Failed to open file"})";
                conn.send(std::move(response));
                return;
            }

            http::response<http::file_body> response{ std::piecewise_construct
                                                    , std::make_tuple(std::move(file))
                                                    , std::make_tuple(http::status::ok, request.version())
                                                    };

            response.set(http::field::server, "GeeCodeX Server");
            response.set(http::field::content_type, "application/pdf");
            response.set(http::field::content_disposition, "attachment; filename=\"" + safe_filename + "\"");

            response.set(http::field::cache_control, "private, no-store, no-cache, must-revalidate, max-age=0");
            response.set(http::field::pragma, "no-cache");

            if (!row["file_size_bytes"].is_null()) response.content_length(row["file_size_bytes"].as<std::int64_t>());
            else {
                auto file_size = file.size();
                response.content_length(file_size);
            }

            conn.send(std::move(response));
            std::cout << "File send successfully" << std::endl;

        } catch (const database::database_exception& e) {
            std::cerr << "database error: " << e.what() << std::endl;
            http::response<http::string_body> response{http::status::internal_server_error, request.version()};
            response.set(http::field::content_type, "application/json");
            response.body() = R"({"error": "Database error", "message:" ")" + std::string(e.what()) + R"("})";
            conn.send(std::move(response));
        }
    } catch (const std::exception& e) {
        std::cerr << "Error in handle_download_pdf: " << e.what() << std::endl;
        
        try {
            auto& request = conn.request();
            http::response<http::string_body> response{http::status::internal_server_error, request.version()};
            response.set(http::field::content_type, "application/json");
            response.body() = R"({"error": "Internal server error", "message": ")" + std::string(e.what()) + R"("})";
            conn.send(std::move(response));
        } catch (...) {
            std::cerr << "Failed to send error response" << std::endl;
        }
    } catch (...) {
        std::cerr << "Unknown exception in handle_download_pdf" << std::endl;

        try {
            auto& request = conn.request();
            http::response<http::string_body> response{http::status::internal_server_error, request.version()};
            response.set(http::field::content_type, "application/json");
            response.body() = R"({"error": "Unknown internal error"})";
            conn.send(std::move(response));
        } catch (...) {
            std::cerr << "Failed to send error response" << std::endl;
        }
    }
}

inline void send_json_error( http_connection& conn
                          , http::status status
                          , const std::string& error_msg
                          , const std::string& detail
                          ){
    try {
        json error_body;
        error_body["error"] = error_msg;
        if (!detail.empty()) error_body["message"] = detail;

        http::response<http::string_body> response{status, conn.request().version()};
        response.set(http::field::server, "GeeCodeX Server");
        response.set(http::field::content_type, "application/json");
        response.keep_alive(false);
        response.body() = error_body.dump();
        response.prepare_payload();
        conn.send(std::move(response));
    } catch (...) {
        std::cerr << "Failed to send JSON error response" << std::endl;
    }
}

inline std::string guess_mime_type(const std::string& extension) {
    std::string ext_lower = boost::algorithm::to_lower_copy(extension);
    if (ext_lower == ".png") return "image/png";
    if (ext_lower == ".jpg" || ext_lower == ".jpeg") return "image/jpeg";
    if (ext_lower == ".gif") return "image/gif";
    if (ext_lower == ".webp") return "image/webp";
    if (ext_lower == ".svg") return "image/svg+xml";
   
    if (ext_lower == ".apk") return "application/vnd.android.package-archive";
    if (ext_lower == ".ipa") return "application/octet-stream";

    return "application/octet-stream";
}

inline void handle_fetch_pdf_cover(http_connection& conn) {
    try {
        std::cout << "Handling PDF cover request (from file path)" << std::endl;
        auto& request = conn.request();

        std::string target = std::string(request.target());
        std::cout << "Target path: " << target << std::endl;
        
        std::regex id_pattern("/geecodex/books/cover/(\\d+)");
        std::smatch matches;


        if (!std::regex_match(target, matches, id_pattern) || matches.size() < 2) {
            std::cout << "Invalid cover path format: " << target << std::endl;
            send_json_error(conn, http::status::bad_request, "Invalid book ID format");
            return;
        }

        int book_id = 0;
        try {
            book_id = std::stoi(matches[1].str());
        } catch (const std::exception& e) {
            std::cerr << "Failed to parse book ID: " << matches[1].str() << " - " << e.what() << std::endl;
            send_json_error(conn, http::status::bad_request, "Invalid book ID format", e.what());
            return;
        }
    
        std::cout << "Book ID: " << book_id << std::endl;

        std::string cover_path_str;

        bool is_active = false;

        try {
            pqxx::result result = execute_params(
                "SELECT cover_path, is_active FROM codex_books WHERE id = $1",
                book_id
            );

            if (result.empty()) {
                std::cout << "Book not found for cover: ID " << book_id << std::endl;
                send_json_error(conn, http::status::not_found, "Book not found");
                return;
            }

            const auto& row = result[0];
            if (row["cover_path"].is_null()) {
                std::cout << "Cover path is NULL for book ID: " << book_id << std::endl;
                send_json_error(conn, http::status::not_found, "Cover image not available for this book");
                return;
            }

            cover_path_str = row["cover_path"].as<std::string>();
            is_active = row["is_active"].as<bool>();
            
            std::cout << "Found book for cover. Path: " << cover_path_str 
                      << ", Active: " << is_active << std::endl;

            if (!is_active) {
                send_json_error(conn, http::status::forbidden, "This book is currently unavailable");
                return;
            }

            if (cover_path_str.empty()) {
                std::cout << "Cover path is empty for book ID: " << book_id << std::endl;
                send_json_error(conn, http::status::not_found, "Cover image path is invalid");
                return;
            }
        } catch (const database::database_exception& e) {
            std::cerr << "Database error fetching book cover path: " << e.what() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "Database error", e.what());
            return;
        } catch (const std::exception& e) {
            std::cerr << "Error during database query for cover path: " << e.what() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "Database query error", e.what());
            return;
        }

        fs::path cover_file_path(cover_path_str);

        if (!fs::exists(cover_file_path) || !fs::is_regular_file(cover_file_path)) {
            std::cerr << "Cover file not found or is not a regular file on server: " 
                      << cover_path_str << std::endl;
            send_json_error(conn, http::status::not_found, "Cover file not found on server");
            return;
        }

        std::string mime_type = guess_mime_type(cover_file_path.extension().string());
        std::cout << "Guessed MIME type: " << mime_type << " for " 
                  << cover_file_path.filename().string() << std::endl;

        beast::error_code ec;
        http::file_body::value_type file_body;
        file_body.open(cover_file_path.string().c_str(), beast::file_mode::read, ec);

        if (ec) {
            std::cerr << "Error opening cover file '" << cover_path_str << "': "<< ec.message() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "Failed to open cover file");
            return;
        }

        const auto file_size = file_body.size();

        http::response<http::file_body> response{
            std::piecewise_construct, 
            std::make_tuple(std::move(file_body)),
            std::make_tuple(http::status::ok, request.version())};

        response.set(http::field::server, "GeeCodeX Server");
        response.set(http::field::content_type, mime_type);
        response.content_length(file_size);
        response.set(http::field::cache_control, "public, max-age=86400");
        response.keep_alive(false);

        conn.send(std::move(response));
        std::cout << "Cover file sent successfully: " << cover_path_str << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error in handle_fetch_pdf_cover: " << e.what() << std::endl;
        send_json_error(conn, http::status::internal_server_error, "Internal server error", e.what());
    } catch (...) {
        std::cerr << "Unknown exception in handle_fetch_pdf_cover" << std::endl;
        send_json_error(conn, http::status::internal_server_error, "Unknown internal error");
    }
}

inline void handle_fetch_latest_books(http_connection& conn) {
    try {
        std::cout << "Handling fetch latest books request" << std::endl;
        auto& request = conn.request();

        std::string sql = 
            "SELECT "
            "   id, title, author, isbn, publisher, publish_date, language, "
            "   page_count, description, created_at, tags, download_count "
            "FROM "
            "   codex_books "
            "WHERE "
            "   is_active = TRUE "
            "   ORDER BY "
            "   created_at DESC "
            "LIMIT 5;";

        pqxx::result result;
        try {
            result = execute_query(sql);
            std::cout << "Fetched " << result.size() << " latest books from database." << std::endl;
        } catch (const database::database_exception& e) {
            std::cerr << "Database error fetching latest books: " << e.what() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "Database error", e.what());
            return;
        } catch (const std::exception& e) {
            std::cerr << "Error during database query for latest books: " << e.what() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "Database query error", e.what());
            return;
        }

        json json_response = json::array();
        for (const auto& row: result) {
            json book_obj;

            book_obj["id"] = row["id"].as<int>();
            book_obj["title"] = row["title"].as<std::string>();

            if (!row["author"].is_null()) book_obj["author"] = row["author"].as<std::string>();
            else book_obj["author"] = nullptr;

            if (!row["isbn"].is_null()) book_obj["isbn"] = row["isbn"].as<std::string>();
            else book_obj["isbn"] = nullptr;

            if (!row["publisher"].is_null()) book_obj["publisher"] = row["publisher"].as<std::string>();
            else book_obj["publisher"] = nullptr;

            if (!row["publish_date"].is_null()) book_obj["publish_date"] = row["publish_date"].as<std::string>();
            else book_obj["publish_date"] = nullptr;

            if (!row["language"].is_null()) book_obj["language"] = row["language"].as<std::string>();
            else book_obj["language"] = nullptr;

            if (!row["page_count"].is_null()) book_obj["page_count"] = row["page_count"].as<int>();
            else book_obj["page_count"] = nullptr;

            if (!row["description"].is_null()) book_obj["description"] = row["description"].as<std::string>();
            else book_obj["description"] = nullptr;

            if (!row["created_at"].is_null()) book_obj["created_at"] = row["created_at"].as<std::string>();
            else book_obj["created_at"] = nullptr;

            json tags_array = json::array();
            if (!row["tags"].is_null()) {
                pqxx::array_parser parser = row["tags"].as_array();
                std::pair<pqxx::array_parser::juncture, std::string> elem;
                do {
                    elem = parser.get_next();
                    if (elem.first == pqxx::array_parser::juncture::string_value) 
                        tags_array.push_back(elem.second);
                } while (elem.first != pqxx::array_parser::juncture::done);
            } 
            book_obj["tags"] = tags_array;

            if (!row["download_count"].is_null()) book_obj["download_count"] = row["download_count"].as<int>();
            else book_obj["download_count"] = 0;

            json_response.push_back(book_obj);
        }

        http::response<http::string_body> response{http::status::ok, request.version()};
        response.set(http::field::server, "GeeCodeX Server");
        response.set(http::field::content_type, "application/json");
        response.keep_alive(false);
        response.body() = json_response.dump(4);
        response.prepare_payload();
        
        conn.send(std::move(response));
        std::cout << "Latest books response sent successfully." << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error in handle_fetch_latest_books: " << e.what() << std::endl;
        send_json_error(conn, http::status::internal_server_error, "Internal server error", e.what());
    } catch (...) {
        std::cerr << "Unknown exception in handle_fetch_latest_books" << std::endl;
        send_json_error(conn, http::status::internal_server_error, "Unknown internal error");
    }
}

struct semantic_version {
    int major = 0;
    int minor = 0;
    int patch = 0;

    static std::optional<semantic_version> from_string(const std::string& version_str) {
        semantic_version ver;
        std::vector<std::string> parts;
        boost::split(parts, version_str, boost::is_any_of("."));

        if (parts.size() != 3) return std::nullopt;

        auto parse_int = [&](const std::string& s, int& out) {
            auto result = std::from_chars(s.data(), s.data() + s.size(), out);
            return result.ec == std::errc() && result.ptr == s.data() + s.size();
        };

        if (!parse_int(parts[0], ver.major) || 
            !parse_int(parts[1], ver.minor) ||
            !parse_int(parts[2], ver.patch)) return std::nullopt;

        return ver;
    }

    bool operator>(const semantic_version& other) const {
        if (major != other.major) return major > other.major;
        if (minor != other.minor) return minor > other.minor;
        return patch > other.patch;
    }

    bool operator<=(const semantic_version& other) const {
        return !(*this > other);
    }

    bool operator==(const semantic_version& other) const {
        return major == other.major && 
               minor == other.minor && 
               patch == other.patch;
    }
};

inline void handle_app_update_check(http_connection &conn) {
    try {
        std::cout << "Handling app update check request" << std::endl;
        auto& request = conn.request();


        auto it = request.find(http::field::content_type);
        if (it == request.end()) {
            send_json_error( conn, http::status::unsupported_media_type
                           , "Invalid Content-Type", "Expected application/json");
            return;
        }


        boost::string_view content_type_value = it->value();
        if (!boost::algorithm::istarts_with(content_type_value, "application/json")) {
            std::cerr << "Invalid Content-Type received: " << content_type_value << std::endl;
            send_json_error( conn, http::status::unsupported_media_type
                           , "Invalid Content-Type", "Expected application/json media type");
            return;
        }

        json request_body;
        try {
            request_body = json::parse(request.body());
        } catch (const json::parse_error& e) {
            std::cerr << "JSON parse error: " << e.what() << std::endl;
            send_json_error( conn, http::status::bad_request
                           , "Invalid JSON format", e.what());
            return;
        }

        if (!request_body.contains("current_version") || 
            !request_body["current_version"].is_string() ||
            !request_body.contains("platform") || 
            !request_body["platform"].is_string()) {
            send_json_error( conn, http::status::bad_request
                           , "Missing or invalid fields"
                           , "Requires 'current_version' (string) and 'platform' (string)");
            return;
        }

        std::string current_version_str = request_body["current_version"];
        std::string platform  = request_body["platform"];
        boost::algorithm::to_lower(platform);

        std::cout << "Client platform: " << platform 
                  << ", Current Version: " << current_version_str
                  << std::endl;

        auto current_version_opt = semantic_version::from_string(current_version_str);
        if (!current_version_opt) {
            send_json_error( conn, http::status::bad_request
                           , "Invalid version format"
                           , "Version must be in x.y.z format (e.g. 1.0.2)");
            return;
        }
        semantic_version current_version = *current_version_opt;

        pqxx::result db_result;
        try {
            std::cout << "Querying database for latest active version for platform: " << platform << std::endl;
            db_result = execute_params(
                "SELECT version_name, version_code, release_notes, is_mandatory "
                "FROM app_updates "
                "WHERE platform = $1 AND is_active = TRUE "
                "ORDER BY version_code DESC "
                "LIMIT 1",
                platform
            );
        } catch (const database::database_exception& e) {
            std::cerr << "Database error fetching latest app version: " << e.what() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "Database error", e.what());
            return;
        } catch (const std::exception& e) {
            std::cerr << "Error during database query for latest app version: " << e.what() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "Database query error", e.what());
            return;
        }

        json json_response;
        if (db_result.empty()) {
            std::cout << "No active update found for platform: " << platform << std::endl;
            json_response["update_available"] = false;
        } else {
            const auto& latest_row = db_result[0];
            std::string latest_version_str = latest_row["version_name"].as<std::string>();
            
            auto latest_version_opt = semantic_version::from_string(latest_version_str);
            if (!latest_version_opt) {
                std::cerr << "CRITICAL: Invalid versions format ('" << latest_version_str 
                          << "') found in database for platform '" << platform << "'!" << std::endl;
                send_json_error( conn, http::status::internal_server_error
                               , "Server configuration error", "Invalid version format in database.");
                return;
            }
            semantic_version latest_version = *latest_version_opt;
            
            std::cout << "Latest DB version: " << latest_version_str 
                      << " (" << latest_version.major 
                      << "."  << latest_version.minor 
                      << "."  << latest_version.patch << ")" 
                      << std::endl;

            std::cout << "Client Version: " << current_version_str 
                      << " (" << current_version.major
                      << "."  << current_version.minor
                      << "."  << current_version.patch
                      << std::endl;
            
            if (latest_version > current_version) {
                std::cout << "Update available" << std::endl;
                json_response["update_available"] = true;
                json_response["latest_version"] = latest_version_str;
                json_response["version_code"] = latest_row["version_code"].as<int>();
                json_response["release_notes"] = latest_row["release_notes"].is_null() ? "" : latest_row["release_notes"].as<std::string>();
                json_response["is_mandatory"] = latest_row["is_mandatory"].as<bool>();
            } else {
                std::cout << "No update needed (client version is current or newer)." << std::endl;
                json_response["update_available"] = false;
            }

            http::response<http::string_body> response{http::status::ok, request.version()};
            response.set(http::field::server, "GeeCodeX Server");
            response.set(http::field::content_type, "application/json");
            response.keep_alive(false);
            response.body() = json_response.dump();
            response.prepare_payload();

            conn.send(std::move(response));
            std::cout << "App update check response send successfully." << std::endl;
        }
    } catch (const std::exception& e) {
        std::cerr << "Error in handle_app_update_check: " << e.what() << std::endl;
        try {
            send_json_error(conn, http::status::internal_server_error, "internal_server_error", e.what());
        } catch (...) {
            std::cerr << "Failed to send error response in handle_app_update_check main catch block" << std::endl;
            beast::error_code ignored_ec;
            conn.socket().shutdown(tcp::socket::shutdown_send, ignored_ec);
        }
    } catch (...) {
        std::cerr << "Unknown exception in handle_app_update_check" << std::endl;
        try {
            send_json_error(conn, http::status::internal_server_error, "Unknown internal error");
        } catch (...) {
            std::cerr << "Failed to send error response in handle_app_update_check unknown catch block" << std::endl;
            beast::error_code ignored_ec;
            conn.socket().shutdown(tcp::socket::shutdown_send, ignored_ec);
        }
    }
}

inline void handle_download_latest_app(http_connection& conn) {
    try {
        std::cout << "Handling latest app download request" << std::endl;
        auto& request = conn.request();
        std::string target = std::string(request.target());

        std::regex platform_regex("/geecodex/app/download/latest/([a-zA-Z0-9_\\-]+)");
        std::smatch match;
        std::string platform;

        if (std::regex_match(target, match, platform_regex) && match.size() == 2) {
            platform = match[1].str();
            boost::algorithm::to_lower(platform);
            std::cout << "Requested platform: " << platform << std::endl;
        } else {
            std::cerr << "Invalid download path format: " << target << std::endl;
            send_json_error(conn, http::status::bad_request, "Invalid URL format", "Expected /geecodex/app/download/latest/{platform}");
            return;
        }

        pqxx::result db_result;
        try {
            std::cout << "Querying database for latest package path for platform: " << platform << std::endl;
            db_result = execute_params(
                "SELECT version_name, package_path "
                "FROM app_updates "
                "WHERE platform = $1 AND is_active = TRUE AND package_path IS NOT NULL AND package_path <> '' "
                "ORDER BY version_code DESC "
                "LIMIT 1",
                platform
            );
            std::cout << "Database query returned " << db_result.size() << " rows for package path." << std::endl;
        } catch (const database::database_exception& e) {
            std::cerr << "Database error fetching package path: " << e.what() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "Database error", e.what());
            return;
        } catch (const std::exception& e) {
            std::cerr << "Error during database query for package path: " << e.what() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "Database query error", e.what());
            return;
        }

        if (db_result.empty()) {
            std::cout << "No active package path found for platform: " << platform << std::endl;
            send_json_error(conn, http::status::not_found, "Package not found", "No downloadable available for this platform");
            return;
        }

        const auto& latest_row = db_result[0];
        std::string package_path_str = latest_row["package_path"].as<std::string>();
        std::string version_name = latest_row["version_name"].as<std::string>();

        std::cout << "Found package_path: " << package_path_str << " for version " << version_name << std::endl;
        fs::path package_file_path(package_path_str);
        beast::error_code file_ec;

        if (!fs::exists(package_file_path, file_ec) || !fs::is_regular_file(package_file_path, file_ec)) {
            if (file_ec) std::cerr << "Filesystem error checking path '" << package_path_str << "': " << file_ec.message() << std::endl;
            else std::cerr << "Package file not found or is not a regular file on server: " << package_path_str << std::endl;
            send_json_error(conn, http::status::not_found, "Package file missing", "The application package file could not be found on server.");
            return;
        }

        http::file_body::value_type file_body;
        file_body.open(package_file_path.string().c_str(), beast::file_mode::read, file_ec);
        
        if (file_ec) {
            std::cerr << "Error opening package file '" << package_path_str << ": " << file_ec.message() << std::endl;
            send_json_error(conn, http::status::internal_server_error, "File access error", "Failed to open the package file");
            return;
        }

        std::string file_extension = package_file_path.extension().string();
        std::string mime_type = guess_mime_type(file_extension);

        std::string download_filename = "GeeCodexApp-" + platform + "-" + version_name + file_extension;
        download_filename = std::regex_replace(download_filename, std::regex("[^a-zA-Z0-9_.-]"), "_");
        
        std::cout << "Sending file: " << download_filename << " (MIME: " << mime_type << ")" << std::endl;

        http::response<http::file_body> response {
            std::piecewise_construct,
            std::make_tuple(std::move(file_body)),
            std::make_tuple(http::status::ok, request.version())
        };

        response.set(http::field::server, "GeeCodeX Server");
        response.set(http::field::content_type, mime_type);
        response.content_length(response.body().size());
        response.set(http::field::content_disposition, "attachment; filename=\"" + download_filename + "\"");

        response.set(http::field::cache_control, "no-cache, no-store, must-revalidate");
        response.set(http::field::pragma, "no-cache");
        response.set(http::field::expires, "0");

        response.keep_alive(false);
        
        conn.send(std::move(response));
        std::cout << "Package file sent successfully: " << package_path_str << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error in handle_download_latest_app: " << e.what() << std::endl;;
        try {
            send_json_error(conn, http::status::internal_server_error, "Internal server error", e.what());
        } catch (...) {
            std::cerr << "Failed to send error response in handle_download_latest_app main catch block" << std::endl;
            beast::error_code ignored_ec;
            conn.socket().shutdown(tcp::socket::shutdown_send, ignored_ec);
        }
    } catch (...) {
        std::cerr << "Unknown exception  in handle_download_latest_app" << std::endl;
        try {
            send_json_error(conn, http::status::internal_server_error, "Unknown internal error");
        } catch (...) {
            std::cerr << "Failed to send error response in handle_download_latest_app unknown catch block." << std::endl;
            beast::error_code ignored_ec;
            conn.socket().shutdown(tcp::socket::shutdown_send, ignored_ec);
        }
    }
}

inline bool check_content_type_is_json(http_connection& conn) {
    auto const& request = conn.request();
    
    auto it = request.find(http::field::content_type);
    if (it == request.end()) {
        std::cerr << "Request missing Content-Type header." << std::endl;
        send_json_error( conn, http::status::unsupported_media_type
                       , "Missing Content-Type"
                       , "Header 'Content-Type: application/json' is required.");
        return false;
    }

    boost::string_view content_type_value = it->value();
    
    if (!boost::algorithm::istarts_with(content_type_value, "application/json")) {
        std::cerr << "Invalid Content-Type received: " << content_type_value << std::endl;
        send_json_error( conn, http::status::unsupported_media_type
                       , "Invalid Content-Type"
                       , "Expected 'application/json' media type.");
        return false;
    }
    return true;
}


inline void handle_fetch_client_feedback(http_connection &conn) {
    try {
        std::cout << "Handling client feedback submission request" << std::endl;
        auto& request = conn.request();

        if (!check_content_type_is_json(conn)) return;

        json request_body;
        try {
            request_body = json::parse(request.body());
        } catch (const json::parse_error& e) {
            std::cerr << "JSON parse error: " << e.what() << std::endl;
            send_json_error( conn, http::status::bad_request
                           , "Invalid JSON format",  e.what());
            return;
        }

        if (!request_body.contains("feedback") ||
            !request_body["feedback"].is_string() || 
            request_body["feedback"].get<std::string>().empty()) {
            send_json_error( conn, http::status::bad_request
                           , "Missing or invalid field", "Requires non-empty 'feedback' (string) field.");        
            return;
        }

        std::string feedback_text = request_body["feedback"];
        std::string nickname = "Anonymous";

        if (request.body().contains("nickname") && request_body["nickname"].is_string()) {
            std::string temp_nickname = request_body["nickname"];
            boost::algorithm::trim(temp_nickname);
            if (!temp_nickname.empty()) {
                nickname = temp_nickname;
                if (nickname.length() > 100) {
                    nickname = nickname.substr(0, 100);
                    std::cout << "Warning: Truncated nickname to 100 characters." << std::endl;
                }
            }
        }

        std::cout << "Received feedback from: " << nickname
                  << "', Feedback: '" << feedback_text.substr(0, 50) << "..."
                  << std::endl;

        try {
            const std::string sql = 
                "INSERT INTO client_feedback (nickname, feedback_text) VALUES ($1, $2)";
            
            execute_transaction([&](pqxx::work& txn) {
                txn.exec_params(sql, nickname, feedback_text);
            });

            std::cout << "Feedback from " << nickname 
                      << "' stored successfully in the database." << std::endl;
        } catch (const database_exception& e) {
            std::cerr << "Database error storing feedback: " << e.what() << std::endl;
            send_json_error( conn, http::status::internal_server_error
                           , "Database error", "Failed to store feedback.");
            return;
        } catch (const std::exception& e) {
            std::cerr << "Error during database insert for feedback: " << e.what() << std::endl;
            send_json_error( conn, http::status::internal_server_error
                           , "Database insert error", "An unexpected error occurred when storing feedback.");
            return;
        }

        json json_response;
        json_response["status"] = "success";
        json_response["message"] = "Feedback received successfully. Thank you!";

        http::response<http::string_body> response{http::status::ok, request.version()};
        response.set(http::field::server, "GeeCodeX Server");
        response.set(http::field::content_type, "application/json");
        response.keep_alive(false);
        response.body() = json_response.dump();
        response.prepare_payload();

        conn.send(std::move(response));
        std::cout << "Client feedback success response sent." << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error in handle_fetch_client_feedback: " << e.what() << std::endl;
        try {
            if (!conn.socket().is_open()) return;
            if (!conn.response_sent()) send_json_error(conn, http::status::internal_server_error, "Internal server error", e.what());
        } catch (...) {
            std::cerr << "Failed to send error  response in handle_fetch_cilent_feedback main catch block." << std::endl;
            beast::error_code ignored_ec;
            conn.socket().shutdown(tcp::socket::shutdown_both, ignored_ec);
            conn.socket().close(ignored_ec);
        }
    } catch (...) {
        std::cerr << "Unknown exception in handle_fetch_client_feedback" << std::endl;
        try {
            if (!conn.socket().is_open()) return;
            if (!conn.response_sent()) send_json_error(conn, http::status::internal_server_error, "Unknown internal error");
        } catch (...) {
            std::cerr << "Failed to send error response in handle_fetch_client_feedback unknown catch block." << std::endl;
            beast::error_code ignored_ec;
            conn.socket().shutdown(tcp::socket::shutdown_both, ignored_ec);
            conn.socket().close(ignored_ec);
        }
    }
}

inline ssl::context& get_shared_ssl_context() {
    static ssl::context ssl_ctx{ssl::context::tlsv13_client};
    static std::once_flag init_flag;

    std::call_once(init_flag, []() {
        try {
            std::cout << "Initializing shared SSL context..." << std::endl;
            ssl_ctx.set_default_verify_paths();

            ssl_ctx.set_verify_mode(ssl::verify_peer);
            std::cout << "Shared SSL context initialized successfully." << std::endl;
        } catch (const std::exception& e) {
            std::cerr << "CRITICAL ERROR: Failed to initialize shared SSL context: " << e.what() << std::endl;
            throw;
        }
    });
    return ssl_ctx;
}

inline std::string get_deepseek_api_key() {
    const char* key = std::getenv("DEEPSEEK_API_KEY");
    std::cout << "DEEPSEEK_API_KEY: " << key << std::endl;
    if (key == nullptr || std::string(key).empty()) {
        std::cerr << "CRITICAL ERROR: DEEPSEEK_API_KEY environment variable not set or empty." << std::endl;
        throw std::runtime_error("DEEPSEEK_API_KEY environment variable not set or empty");
    }
    return std::string(key);
}


inline void handle_ai_chat(http_connection &conn) {
    bool response_sent_flag = false;
    
    try {
        std::cout << "Handling AI chat request" << std::endl;

        if (!check_content_type_is_json(conn)) {
            response_sent_flag = true;
            return;
        }

        json request_body;
        try {
            request_body = json::parse(conn.request().body());
        } catch (const json::parse_error& e) {
            std::cerr << "AI Chat JSON parse error: " << e.what() << std::endl;
            send_json_error(conn, http::status::bad_request, "Invalid JSON format", e.what());
            response_sent_flag = true;
            return;
        }

        if (!request_body.contains("messages") ||
            !request_body["messages"].is_array() || 
            request_body["messages"].empty()) {
                send_json_error(conn, http::status::bad_request, "Invalid request format", "Missing or invalid 'messages' array");
                response_sent_flag = true;
                return;
            }
        
        for (const auto& msg: request_body["messages"]) {
            if (!msg.is_object() ||
                !msg.contains("role") || 
                !msg["role"].is_string() ||
                !msg.contains("content") || 
                !msg["content"].is_string()) {
                    send_json_error(conn, http::status::bad_request, "Invalid request format", "Invalid structure within 'messages' array.");
                    response_sent_flag = true;
                    return;
                }
        }

        json deepseek_request_body;
        deepseek_request_body["model"] = request_body.value("model", "deepseek-chat");
        deepseek_request_body["messages"] = request_body["messages"];
        deepseek_request_body["stream"] = false;

        std::string api_key = get_deepseek_api_key();
        
        ssl::context& shared_ssl_ctx = get_shared_ssl_context();

        std::cout << "Launching deepseek_session..." << std::endl;
        std::make_shared<deepseek_session>(
            conn.socket().get_executor(),
            shared_ssl_ctx,
            conn.shared_from_this()
        )->run("/chat/completions", deepseek_request_body.dump(), api_key);
        std::cout << "Exiting handle_ai_chat handler function (async request launched)." << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error in handle_ai_chat setup: " << e.what() << std::endl;
        if (!response_sent_flag) {
            try {
                send_json_error(conn, http::status::internal_server_error, "Internal Server Error", e.what());
            } catch (...) { }
        }
    } catch (...) {
        std::cerr << "Unknown exception during handle_ai_chat setup" << std::endl;
        if (!response_sent_flag) {
            try {
                send_json_error(conn, http::status::internal_server_error, "Unknown Internal Error");
            } catch (...) { }
        }
    }
}




inline void handle_score_book(http_connection &conn) {

}

inline void handle_comment_book(http_connection &conn) {

}


inline void handle_content_recognize(http_connection &conn) {

}


}
#endif // HTTP_IMPL_HPP

