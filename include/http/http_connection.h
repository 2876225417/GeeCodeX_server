#ifndef HTTP_CONNECTION_H
#define HTTP_CONNECTION_H


#include <boost/asio/any_io_executor.hpp>
#include <boost/asio/error.hpp>
#include <boost/beast/core/bind_handler.hpp>
#include <boost/beast/core/error.hpp>
#include <boost/beast/core/flat_buffer.hpp>
#include <boost/beast/core/stream_traits.hpp>
#include <boost/beast/core/tcp_stream.hpp>
#include <boost/beast/http.hpp>
#include <boost/beast/http/field.hpp>
#include <boost/beast/http/file_body_fwd.hpp>
#include <boost/beast/http/message_fwd.hpp>
#include <boost/beast/http/status.hpp>
#include <boost/beast/http/string_body_fwd.hpp>
#include <boost/beast/http/verb.hpp>
#include <boost/beast/http/write.hpp>
#include <boost/beast/ssl/ssl_stream.hpp>
#include <boost/core/ignore_unused.hpp>
#include <boost/mp11/set.hpp>
#include <boost/system/detail/errc.hpp>
#include <boost/beast/ssl.hpp>
#include <boost/asio/ssl/error.hpp>
#include <boost/asio/ssl/context.hpp>
#include <boost/asio/ssl/stream.hpp>
#include <database/db_conn.h>
#include <database/db_ops.hpp>
#include <exception>
#include <http/router.hpp>

#include <pqxx/internal/statement_parameters.hxx>
#include <pqxx/result.hxx>

#include <json.hpp>

#include <future>
#include <memory>
#include <stdexcept>
#include <sys/socket.h>
#include <utility>
#include <iostream>
#include <chrono>
#include <random>

namespace geecodex::http {
using json      = nlohmann::json;
using namespace geecodex::database;
namespace net = boost::asio;
namespace ssl = net::ssl;
using tcp = net::ip::tcp;


void send_json_error( http_connection& conn
    , http::status status
    , const std::string& error_msg
    , const std::string& detail = ""
    );

static const auto server_start_time = std::chrono::steady_clock::now();

inline long get_server_uptime() {
    auto now = std::chrono::steady_clock::now();
    return std::chrono::duration_cast<std::chrono::seconds>(now - server_start_time).count();
}

class http_connection: public std::enable_shared_from_this<http_connection> {
public:     
    http_connection(tcp::socket socket)
        : m_socket{std::move(socket)} 
        , m_response_sent{false} {}
    void start() { 
        try { 
            read_request();
        } catch (const std::exception& e) {
            std::cerr << "Exception in start(): " << e.what() << std::endl;
        } catch (...) {
            std::cerr << "Unknown exception in start()" << std::endl;
        }
    }

    tcp::socket& socket() { return m_socket; }
    http::request<http::string_body>& request() { return m_request; }
    http::response<http::string_body>& response() { return m_response; }
    bool response_sent() const { return m_response_sent; }

    void send(http::response<http::string_body>&& response) {
        try {
            auto shared_response = std::make_shared<http::response<http::string_body>>(std::move(response));
            auto self = shared_from_this();
            m_response_sent = true;
            shared_response->prepare_payload();
            
            http::async_write(m_socket, *shared_response, [self, shared_response](beast::error_code ec, std::size_t bytes) { 
                try {
                    if (ec) std::cerr << "Error writing response: " << ec.message() << '\n';
                    else std::cout << "Response sent successfully (" << bytes << " bytes)" << std::endl;

                    beast::error_code shutdown_ec;
                    self->m_socket.shutdown(tcp::socket::shutdown_send, shutdown_ec);
                    if (shutdown_ec && shutdown_ec != beast::errc::not_connected) {
                        std::cerr << "Error shutting down socket: " << shutdown_ec.message() << '\n'; 
                    } else std::cout << "Socket shutdown successfully" << std::endl;
                } catch (const std::exception& e) {
                    std::cerr << "Exception in send completion handler: " << e.what() << '\n';
                } catch (...) {
                    std::cerr << "Unknown exception in send completion hanlder" << '\n';
                }
            });
        } catch (const std::exception& e) {
            std::cerr << "Exception in send(string_body): " << e.what() << '\n';
            try {
                if (!m_response_sent) {
                    http::response<http::string_body> 
                        error_response{http::status::internal_server_error, m_request.version()};
                    error_response.set(http::field::content_type, "application/json");
                    error_response.body() = R"({"error": "Failed to send response"})";
                    error_response.prepare_payload();

                    m_socket.write_some(net::buffer(error_response.body()));
                    m_socket.shutdown(tcp::socket::shutdown_send);
                }
            } catch (...) {
                std::cerr << "failed to send error response" << '\n';
            }     
        } catch(...) {
            std::cerr << "Unknown exception in send(string_body)" << '\n';
        }
    }  

    void send(http::response<http::file_body>&& response) {
        try {
            auto shared_response = std::make_shared<http::response<http::file_body>>(std::move(response));
            auto self = shared_from_this();
            m_response_sent = true;
        
            std::cout << "Starting file transfer Size: " 
                      << (shared_response->body().size() / (1024.f * 1024.f))
                      << " MB" << std::endl; 

            http::async_write( m_socket, *shared_response
                             , [self, shared_response](beast::error_code ec, std::size_t bytes) {
                                    try {
                                        if (ec) std::cerr << "Error writing file response: " << ec.message() << '\n';
                                        else std::cout << "File response sent successfully ("
                                                       << (bytes / (1024.f * 1024.f))
                                                       << " MB)" << std::endl;

                                        if (!ec) {
                                            beast::error_code shutdown_ec;
                                            self->m_socket.shutdown(tcp::socket::shutdown_send, shutdown_ec);
                                            if (shutdown_ec && shutdown_ec != beast::errc::not_connected)
                                                std::cerr << "Error shutting down socket: " << shutdown_ec.message() << '\n';
                                            else std::cout << "Socket shutdown successfully" << std::endl;
                                        }
                                    } catch (const std::exception& e) {
                                        std::cerr << "Exception in file send completion handler: " << e.what() << '\n';
                                    } catch (...) { 
                                        std::cerr << "Unknown exception in file send completion handler" << '\n';
                                    }
                             });

        } catch (const std::exception& e) {
            std::cerr << "Exception in send(file_body): " << e.what() << std::endl;
            try {
                if (!m_response_sent) {
                    http::response<http::string_body> 
                        error_response{http::status::internal_server_error, m_request.version()};
                    error_response.set(http::field::content_type, "application/json");
                    error_response.body() = R"({"error": "Failed to send file response"})";
                    error_response.prepare_payload();

                    m_socket.write_some(net::buffer(error_response.body()));
                    m_socket.shutdown(tcp::socket::shutdown_send);
                }
            } catch (...) {
                std::cerr << "Failed to send error response" << '\n';
            }
        } catch (...) {
            std::cerr << "Unknown exception in send(file_body)" << '\n';
        }
    }

private: 
    tcp::socket                         m_socket;
    beast::flat_buffer                  m_buffer{8192};
    http::request<http::string_body>    m_request;
    http::response<http::string_body>   m_response;
    bool                                m_response_sent;

    
    void read_request() {
        auto self = shared_from_this();
                        
        http::async_read( m_socket
                        , m_buffer
                        , m_request
                        , [self]( beast::error_code ec
                                        , std::size_t bytes_transferred) { 
                                            boost::ignore_unused(bytes_transferred);
                                            try {
                                                if (!ec) self->process_request();
                                                else std::cerr << "Error reading request :" << ec.message() << "\n";    
                                            } catch (const std::exception& e) {
                                                std::cerr << "Exception in read_request completion handler: " << e.what() << '\n';
                                            } catch (...) {
                                                std::cerr << "Unknown exception in read_request completion handler" << '\n';
                                            }
                                        }); 
    }

    void process_request() {
        try {
            m_response.version(m_request.version());
            m_response.keep_alive(false);
            std::string_view target(m_request.target().data(), m_request.target().size());
        
            std::cout << "Processing request: " << m_request.method() 
                      << " " << target << std::endl;

            http_method method = enum2method(m_request.method());
            api_route route = route_table.find(target, method);
        
            std::cout << "Route matched: " << static_cast<int>(route) << std::endl;

            m_response.set(http::field::server, "GeeCodeX");
            dispatch_route(route);
        
            if (!m_response_sent) write_response();

        } catch (const std::exception& e) {
            std::cerr << "Exception in process_request: " << e.what() << std::endl;
            try {
                if (!m_response_sent) {
                    m_response.result(http::status::internal_server_error);
                    m_response.set(http::field::content_type, "application/json");
                    m_response.body() = R"({"error": "Internal server error"})";
                    write_response();
                }
            } catch (...) {
                std::cerr << "Failed to send error response" << std::endl;
            }
        } catch (...) {
            std::cerr << "Unknown exception in process_request" << std::endl;
            try {
                if (!m_response_sent) {
                    m_response.result(http::status::internal_server_error);
                    m_response.set(http::field::content_type, "application/json");
                    m_response.body() = R"({"error": "Unknown internal error"})";
                   
                    write_response();
                }
            } catch (...) {
                std::cerr << "Failed to send errror response";
            }
        }
    }

    void dispatch_route(api_route route) {
        try {
            const auto& handlers = get_route_handlers();
            auto it = handlers.find(route);
            if (it != handlers.end()) {
                try {
                    it->second(*this);
                } catch (const std::exception& e) {
                    std::cerr << "Exception in route handler: " << e.what() << std::endl;
                    if (!m_response_sent) {
                        http::response<http::string_body> 
                            response{http::status::internal_server_error, m_request.version()};
                        response.set(http::field::content_type, "application/json");
                        response.body() = R"({"error": "Internal server error", "message": ")" + std::string(e.what()) + R"("})";
                        send(std::move(response));
                    }
                } catch (...) {
                    std::cerr << "Unknown exception in route handler" << std::endl;
                    if (!m_response_sent) {
                        http::response<http::string_body> 
                            response{http::status::internal_server_error, m_request.version()};
                        response.set(http::field::content_type, "application/json");
                        response.body() = R"({"error": "Unknown internal error"})";
                        send(std::move(response));
                    }
                }
            } else handle_not_found(*this);

        } catch (const std::exception& e) {
            std::cerr << "Exception in dispatch_route: " << e.what() << '\n';
            try {
                if (!m_response_sent) {
                    http::response<http::string_body>
                        response{http::status::internal_server_error, m_request.version()};
                    response.set(http::field::content_type, "application/json");
                    response.body() = R"({"error": "Internal routing error"})";
                    send(std::move(response));
                }
            } catch (...) {
                std::cerr << "Failed to send error response" << std::endl;
            } 
        } catch (...) {
            std::cerr << "Unknown exception in dispatch_route" << std::endl;
            try {
                if (!m_response_sent) {
                    http::response<http::string_body>
                        response{http::status::internal_server_error, m_request.version()};
                    response.set(http::field::content_type, "application/json");
                    response.body() = R"({"error": "Unknown internal routing error"})";
                    send(std::move(response));    
                }
            } catch (...) {
                std::cerr << "Failed to send error response" << std::endl;
            }
        }
    }

    void write_response() { 
        try {
            auto self = shared_from_this();    
            m_response.content_length(m_response.body().size());
            m_response_sent = true;

            http::async_write( m_socket, m_response
                             , [self]( beast::error_code ec
                             , std::size_t ) {
                                try {  
                                    if (ec) std::cerr << "Error writing response: " << ec.message() << "\n";
                                    beast::error_code shutdown_ec;
                                    self->m_socket.shutdown(tcp::socket::shutdown_send, shutdown_ec);
                                    if (shutdown_ec && shutdown_ec != beast::errc::not_connected)
                                        std::cerr << "Error shutting down socket: " << shutdown_ec.message() << '\n';
                                } catch (const std::exception& e) {
                                    std::cerr << "Exception in write_response completion handler: " << e.what() << '\n';
                                } catch (...) {
                                    std::cerr << "Unknown exception in write_response completion handler" << '\n';
                                }
                         }); 
        } catch (const std::exception& e) {
            std::cerr << "Exception in write_response: " << e.what() << '\n';
        } catch (...) {
            std::cerr << "Unknown exception in write_response" << '\n';
        }
    }    
};

class deepseek_session: public std::enable_shared_from_this<deepseek_session> {
public:
    explicit deepseek_session( net::any_io_executor executor
                             , ssl::context& ctx
                             , std::shared_ptr<http_connection> org_conn
                             ):m_resolver(executor)
                             , m_ssl_ctx(ctx)
                             , m_stream(executor, ctx)
                             , m_org_connection(org_conn)
                             {
        if (!m_org_connection) throw std::invalid_argument("Original connection connot be null");
        std::cout << "deepseek session created." << std::endl;
    }

    void run( const std::string& target
            , const std::string& body
            , const std::string& api_key) {
        try{
            m_request.method(http::verb::post);
            m_request.target(target);
            m_request.version(11);
            m_request.set(http::field::host, m_deepseek_host);
            m_request.set(http::field::user_agent, "GeeCodeX-Client/1.0");
            m_request.set(http::field::content_type, "application/json");
            m_request.set(http::field::authorization, "Bearer " + api_key);
            m_request.body() = body;
            m_request.prepare_payload();

            if (!SSL_set_tlsext_host_name(m_stream.native_handle(), m_deepseek_host.c_str())) {
                beast::error_code ec{static_cast<int>(::ERR_get_error()), net::error::get_ssl_category()};
                std::cerr << "Failed to set SNI Hostname: " << ec.message() << '\n';
                send_error_to_original_client("SSL Setup Error", "Failed to set SNI");       
            }

            std::cout << "Resolving Deepseek host: " << m_deepseek_host << std::endl;
            m_resolver.async_resolve( m_deepseek_host, m_deepseek_port
                                    , beast::bind_front_handler(&deepseek_session::on_resolve, shared_from_this()));

        } catch (const std::exception& e) {
            std::cerr << "Exception in deepseek_session::run: " << e.what() << std::endl;
            send_error_to_original_client("Internal Server Error", "Failed to initiate AI request setup.");
        } catch (...) {
            std::cerr << "Unknown exception in deepseek_session::run" << std::endl;
            send_error_to_original_client("Internal Server Error", "Unknown error during AI request setup.");
        }
    }
private:
    tcp::resolver m_resolver;
    ssl::context& m_ssl_ctx;
    beast::ssl_stream<beast::tcp_stream> m_stream;
    beast::flat_buffer m_buffer;
    http::request<http::string_body> m_request;
    http::response<http::string_body> m_response;
    std::shared_ptr<http_connection> m_org_connection;
    std::string m_deepseek_host = "api.deepseek.com";
    std::string m_deepseek_port = "443";

    void on_resolve(beast::error_code ec, tcp::resolver::results_type results) {
        if (ec) {
            std::cerr << "DeepSeek Resolve Error: " << ec.message() << std::endl;
            return send_error_to_original_client("AI Service Network Error", "Could not resolve host");
        }
        
        std::cout << "Resolved DeepSeek host. Connecting..." << std::endl;
        beast::get_lowest_layer(m_stream)
            .async_connect( results
                          , beast::bind_front_handler(&deepseek_session::on_connect, shared_from_this()));
    }

    void on_connect(beast::error_code ec, tcp::resolver::results_type::endpoint_type /* endpoint */) {
        if (ec) {
            std::cerr << "DeepSeek Connect Error: " << ec.message() << std::endl;
            return send_error_to_original_client("AI Service Network Error", "Could not connect to host");
        }
        std::cout << "Connected to DeepSeek. Performing SSL handshake..." << std::endl;
        m_stream.async_handshake(ssl::stream_base::client, beast::bind_front_handler(&deepseek_session::on_handshake, shared_from_this()));
    }

    void on_handshake(beast::error_code ec) {
        if (ec) {
            std::cerr << "DeepSeek SSL Handshake Error: " << ec.message() << std::endl;
            return send_error_to_original_client("AI Service Network Error", "SSL handshake failed");
        }
        std::cout << "SSL Handshake successful. Sending request to DeepSeek..." << std::endl;
        http::async_write(m_stream, m_request, beast::bind_front_handler(&deepseek_session::on_write, shared_from_this()));
    }

    void on_write(beast::error_code ec, std::size_t bytes_transferred) {
        boost::ignore_unused(bytes_transferred);
        if (ec) {
            std::cerr << "DeepSeek Write Error: " << ec.message() << std::endl;
            return send_error_to_original_client("AI Service Network Error", "Failed to send request");
        }
        
        std::cout << "Request sendt (" << bytes_transferred << " bytes). Reading response..." << std::endl;
        http::async_read(m_stream, m_buffer, m_response, beast::bind_front_handler(&deepseek_session::on_read, shared_from_this()));
    }

    void on_read(beast::error_code ec, std::size_t bytes_transferred) {
        boost::ignore_unused(bytes_transferred);
        std::cout << "Read finished. Error code: " << ec.message() << ", Bytes read: " << bytes_transferred << std::endl;
        if (ec == http::error::end_of_stream) {
            process_deepseek_response();
            do_shutdown();
            return;    
        } if (ec) {
            std::cerr << "DeepSeek Read Error: " << ec.message() << std::endl;
            send_error_to_original_client("AI Service Network Error", "Failed to read response");
            if (beast::get_lowest_layer(m_stream).socket().is_open()) do_shutdown();
            return;
        }

        process_deepseek_response();
        do_shutdown();
    }

    void do_shutdown() {
        beast::error_code ec;
        
        m_stream.async_shutdown(
            [self = shared_from_this()](beast::error_code ec) {
                if (ec && ec != net::ssl::error::stream_truncated && ec != net::error::eof)
                    std::cerr << "DeepSeek SSL Shutdown Error: " << ec.message() << std::endl;
                else std::cout << "DeepSeek connection shutdown complete." << std::endl;
            }
        );
    }

    void process_deepseek_response() {
        try {
            std::cout << "Received DeepSeek Response Status: " << m_response.result_int() << std::endl;
            
            std::cout << "DeepSeek Headers: " << m_response.base() << std::endl;
            std::cout << "DeepSeek Body: " << m_response.body() << std::endl;
            
            if (m_response.result() != http::status::ok) {
                std::cerr << "DeepSeek API Error Status " << m_response.result_int()
                          << ", Body: " << m_response.body() << std::endl;
                std::string error_message = "Received status: " + std::to_string(m_response.result_int()) + " from AI provider";
                try {
                    json error_json = json::parse(m_response.body());
                    if (error_json.contains("error") && 
                        error_json["error"].is_object() &&
                        error_json["error"].contains("message") &&
                        error_json["error"]["message"].is_string())
                            error_message = "AI Provider Error: " + error_json["error"]["message"].get<std::string>(); 
                } catch (...) { }
                return send_error_to_original_client("AI Service Error", error_message);
            }

            json deepseek_json = json::parse(m_response.body());

            if (!deepseek_json.contains("choices") || 
                 deepseek_json["choices"].empty() || 
                !deepseek_json["choices"].is_array()) 
                return send_error_to_original_client("AI Service Error", "Invalid response format from AI provider (missing choices)");

            const auto& first_choice = deepseek_json["choices"][0];
            if (!first_choice.contains("message") || 
                !first_choice["message"].is_object())
                return send_error_to_original_client("AI Service Error", "Invalid response format from AI provider (missing message in choice)");

            const auto& message = first_choice["message"];
            if (!message.contains("content") || 
                !message["content"].is_string())
                return send_error_to_original_client("AI Service Error", "Invalid response format from AI provider (missing content in message)");

            std::string ai_reply = message["content"].get<std::string>();

            json client_response_body;
            client_response_body["reply"] = ai_reply;
            if (deepseek_json.contains("usage")) client_response_body["usage"] = deepseek_json["usage"];
        
            http::response<http::string_body> response_to_client{http::status::ok, m_org_connection->request().version()};
            response_to_client.set(http::field::server, "GeeCodeX Server");
            response_to_client.set(http::field::content_type, "application/json");
            response_to_client.keep_alive(m_org_connection->request().keep_alive());
            response_to_client.body() = client_response_body.dump();
            response_to_client.prepare_payload();

            m_org_connection->send(std::move(response_to_client));
            std::cout << "Sent AI reply back to original client." << std::endl;
        } catch (const json::parse_error& e) {
            std::cerr << "Failed to parse DeepSeek JSON response: " << e.what() << std::endl;
            send_error_to_original_client("AI Service Error", "Failed to parse AI provider response");
        } catch (const std::exception& e) {
            std::cerr << "Error processing DeepSeek response: " << e.what() << std::endl;
            send_error_to_original_client("Internal Server Error", "Error processing AI response");
        } catch (...) {
            std::cerr << "Unknown error processing DeepSeek response." << std::endl;
            send_error_to_original_client("Internal Server Error", "Unknown error processing AI response");
        }
    }

    void send_error_to_original_client(const std::string& error_type, const std::string& message) {
        bool already_send = false;
        if (m_org_connection->response_sent()) already_send = true;
        
        if (!already_send) {
            try {
                send_json_error(*m_org_connection, http::status::internal_server_error, error_type, message);
                std::cerr << "Sent error to original client: " << error_type << " - " << message << std::endl;
            } catch (const std::exception& e) {
                std::cerr << "Failed to send error response back to original client: " << e.what() << std::endl;
            } catch (...) {
                std::cerr << "Unknown error while trying to send error response back to original client." << std::endl;
            }
        } else std::cerr << "Attempted to send error [" << error_type << "] but response already sent." << std::endl;
    }
};
}   // NAMESPACE GEECODEX
#endif // HTTP_CONNECTION_H
#include <http/http_impl.hpp>
