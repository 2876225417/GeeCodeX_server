#ifndef HTTP_CONNECTION_H
#define HTTP_CONNECTION_H

#include <database/db_conn.h>
#include <future>
#include <memory>
#include <utility>
#include <json.hpp>

#include <database/db_ops.hpp>
#include <boost/beast/core.hpp>
#include <boost/beast/core/error.hpp>
#include <boost/beast/core/flat_buffer.hpp>
#include <boost/beast/http.hpp>
#include <boost/beast/http/field.hpp>
#include <boost/beast/http/fields_fwd.hpp>
#include <boost/beast/http/file_body_fwd.hpp>
#include <boost/beast/http/message_fwd.hpp>
#include <boost/beast/http/status.hpp>
#include <boost/beast/http/string_body_fwd.hpp>
#include <boost/beast/http/verb.hpp>
#include <boost/beast/version.hpp>
#include <boost/asio.hpp>
#include <boost/core/ignore_unused.hpp>
#include <iostream>
#include <chrono>
#include <random>


#include <pqxx/internal/statement_parameters.hxx>

namespace inf_qwq::http {
    using json      = nlohmann::json;
    namespace beast = boost::beast;
    namespace http  = beast::http;
    namespace net   = boost::asio;
    using tcp       = boost::asio::ip::tcp;
    using namespace inf_qwq::database;

    /* ----Route Table Parser---- */
    enum class http_method {
        GET,
        POST,
        PUT,
        DELETE,
        UNKNOWN
    };

    inline http_method enum2method(http::verb method) {
        switch (method) {
            case http::verb::get:       return http_method::GET;
            case http::verb::post:      return http_method::POST;
            case http::verb::put:       return http_method::PUT;
            case http::verb::delete_:   return http_method::DELETE;
            default:                    return http_method::UNKNOWN;
        }
    }
    
    enum class api_route {
        HELLO,
        UNKNOWN
    };

    struct route_info {
        std::string_view path;
        http_method method;
        api_route route;
    };

    template <size_t N>
    struct static_route_table {
        std::array<route_info, N> routes;

        template <size_t... I>
        constexpr static_route_table(const route_info (&init)[N], std::index_sequence<I...>)
            : routes{init[I]...} {}

        constexpr static_route_table(const route_info (&init)[N])
            : static_route_table(init, std::make_index_sequence<N>{}) {}
    
        constexpr api_route find(std::string_view path, http_method method) const {
            for (const auto& route: routes) 
                if (route.path == path && route.method == method) return route.route;   
            return api_route::UNKNOWN;
        }
    };

    static constexpr route_info route_definitions[] = {
        {"/inf_qwq/hello",                          http_method::GET,   api_route::HELLO},
    };
    static constexpr auto route_table = static_route_table(route_definitions);
    /* ----Route Table Parser---- */

    static const auto server_start_time = std::chrono::steady_clock::now();

    inline long get_server_uptime() {
        auto now = std::chrono::steady_clock::now();
        return std::chrono::duration_cast<std::chrono::seconds>(now - server_start_time).count();
    }

    class http_connection;

    void handle_hello(http_connection& conn);
    void handle_health_check(http_connection& conn);
    void handle_get_all_rtsp_sources(http_connection& conn);
    void handle_add_rtsp_source(http_connection& conn) ;
    void handle_update_cropped_coords(http_connection& conn);
    void handle_not_found(http_connection& conn);
    void handle_get_inf_result(http_connection& conn);
    void handle_remove_rtsp_stream(http_connection& conn);

    using route_handler_func = std::function<void(http_connection&)>;
    inline const std::unordered_map<api_route, route_handler_func>& get_route_handlers() {
        static const std::unordered_map<api_route, route_handler_func> handlers = {
            {api_route::HELLO, handle_hello},
            {api_route::UNKNOWN, handle_not_found},
        };
        return handlers;
    }

    class http_connection: public std::enable_shared_from_this<http_connection> {
    public:     
        http_connection(tcp::socket socket): m_socket(std::move(socket)) {}
        void start() { read_request(); }

        tcp::socket& socket() { return m_socket; }
        http::request<http::string_body>& request() { return m_request; }
        http::response<http::string_body>& response() { return m_response; }

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

        }

    





}   // NAMESPACE INF_QWQ
#endif // HTTP_CONNECTION_H
