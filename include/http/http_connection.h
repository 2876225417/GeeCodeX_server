#ifndef HTTP_CONNECTION_H
#define HTTP_CONNECTION_H



#include <boost/beast/core/error.hpp>
#include <boost/beast/http/field.hpp>
#include <boost/beast/http/file_body_fwd.hpp>
#include <boost/beast/http/message_fwd.hpp>
#include <boost/beast/http/status.hpp>
#include <boost/beast/http/string_body_fwd.hpp>
#include <boost/beast/http/write.hpp>
#include <boost/mp11/set.hpp>
#include <boost/system/detail/errc.hpp>
#include <database/db_conn.h>
#include <database/db_ops.hpp>
#include <exception>
#include <http/router.hpp>

#include <pqxx/internal/statement_parameters.hxx>
#include <pqxx/result.hxx>

#include <json.hpp>

#include <future>
#include <memory>
#include <sys/socket.h>
#include <utility>
#include <iostream>
#include <chrono>
#include <random>

namespace geecodex::http {
using json      = nlohmann::json;
using namespace geecodex::database;

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
            auto shared_response = std::make_shared<http::response<http::string_body>>(std::move(response));
            auto self = shared_from_this();
            m_response_sent = true;
            
            http::async_write(m_socket, *shared_response, [self](beast::error_code ec, std::size_t bytes) {
                try {
                    if (ec) std::cerr << "Error writing file response: " << ec.message() << '\n';
                    else std::cout << "File response sent successfully (" << bytes << " bytes)" << std::endl;
                    beast::error_code shutdown_ec;
                    self->m_socket.shutdown(tcp::socket::shutdown_send, shutdown_ec);
                    if (shutdown_ec && shutdown_ec != beast::errc::not_connected) {
                        std::cerr << "Error shutting down socket: " << shutdown_ec.message() << '\n';
                    } else std::cout << "Socket shutdown successfully" << std::endl;
                } catch (const std::exception& e) {
                    std::cerr << "Exception in file send completion handler: " << e.what() << '\n'; 
                } catch (...) {
                    std::cerr << "Unknown exception in file send completion handler" << '\n';
                } 
            });
        } catch( const std::exception& e) {
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


}   // NAMESPACE GEECODEX
#endif // HTTP_CONNECTION_H
#include <http/http_impl.hpp>
