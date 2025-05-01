#ifndef HTTP_CONNECTION_H
#define HTTP_CONNECTION_H



#include <boost/beast/core/error.hpp>
#include <boost/beast/http/file_body_fwd.hpp>
#include <boost/beast/http/message_fwd.hpp>
#include <boost/beast/http/write.hpp>
#include <database/db_conn.h>
#include <database/db_ops.hpp>
#include <http/router.hpp>

#include <pqxx/internal/statement_parameters.hxx>
#include <pqxx/result.hxx>

#include <json.hpp>

#include <future>
#include <memory>
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
    http_connection(tcp::socket socket): m_socket(std::move(socket)) {}
    void start() { read_request(); }

    tcp::socket& socket() { return m_socket; }
    http::request<http::string_body>& request() { return m_request; }
    http::response<http::string_body>& response() { return m_response; }

    void send(http::response<http::string_body>&& response) {
        auto self = shared_from_this();
        response.prepare_payload();
        http::async_write(m_socket, response, [self](beast::error_code ec, std::size_t) { 
            if (ec) std::cerr << "Error writing response: " << ec.message() << '\n';
            self->m_socket.shutdown(tcp::socket::shutdown_send, ec);
            });
    }  

    void send(http::response<http::file_body>&& response) {
        auto self = shared_from_this();
        http::async_write(m_socket, response, [self](beast::error_code ec, std::size_t) {
            if (ec) std::cerr << "Error writing file response: " << ec.message() << '\n';
            self->m_socket.shutdown(tcp::socket::shutdown_send, ec);
        });     
    }

private: 
    tcp::socket                         m_socket;
    beast::flat_buffer                  m_buffer{8192};
    http::request<http::string_body>    m_request;
    http::response<http::string_body>   m_response;

    
    void read_request() {
        auto self = shared_from_this();
                        
        http::async_read( m_socket
                        , m_buffer
                        , m_request
                        , [self]( beast::error_code ec
                                        , std::size_t bytes_transferred) { 
                                            boost::ignore_unused(bytes_transferred);
                                            if (!ec) self->process_request();
                                            else std::cerr << "Error reading request :" << ec.message() << "\n";
                                        }); 
        }

    void process_request() {
        m_response.version(m_request.version());
        m_response.keep_alive(false);
        std::string_view target(m_request.target().data(), m_request.target().size());
        http_method method = enum2method(m_request.method());
        api_route route = route_table.find(target, method);
        m_response.set(http::field::server, "Beast");
        dispatch_route(route);
        write_response();
    }

    void dispatch_route(api_route route) {
        const auto& handlers = get_route_handlers();
        auto it = handlers.find(route);
        if (it != handlers.end()) it->second(*this);
        else handle_not_found(*this);
    }

    void handle_not_found(http_connection& conn) {
        auto& m_response = conn.response();
        m_response.result(http::status::not_found);
        m_response.set(http::field::content_type, "application/json");
        m_response.body() = "Endpoint not found\r\n";   
    }


    void write_response() { 
        auto self = shared_from_this();    
        m_response.content_length(m_response.body().size());
                
        http::async_write( m_socket, m_response
                         , [self]( beast::error_code ec
                         , std::size_t ) {
                            if (ec) std::cerr << "Error writing response: " << ec.message() << "\n";
                                self->m_socket.shutdown(tcp::socket::shutdown_send, ec);
                         });
    }
};

}   // NAMESPACE GEECODEX
#endif // HTTP_CONNECTION_H
#include <http/http_impl.hpp>
