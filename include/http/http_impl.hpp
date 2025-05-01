#ifndef HTTP_IMPL_HPP
#define HTTP_IMPL_HPP

#include "database/db_ops.hpp"
#include <boost/beast/http/field.hpp>
#include <boost/beast/http/message_fwd.hpp>
#include <boost/beast/http/status.hpp>
#include <boost/beast/http/string_body_fwd.hpp>
#include <exception>
#include <json.hpp>
#include <pqxx/pqxx>
#include <http/http_connection.h>
#include <filesystem>
#include <boost/beast/http/file_body.hpp>
#include <regex>

namespace geecodex::http {
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
                conn.send(std::move(response));
                return;
            }

            const auto& row = result[0];
            std::string title = row["title"].as<std::string>();
            std::string pdf_path = row["pdf_path"].as<std::string>();
            bool is_active = row["is_active"].as<bool>();
            int access_level = row["access_level"].as<int>();

            std::cout << "Found book: " << title << ", Path: " << pdf_path << std::endl;
        } catch (const std::exception& e) {

        }

    } catch (const std::exception& e) {

    }
}




}
#endif // HTTP_IMPL_HPP
