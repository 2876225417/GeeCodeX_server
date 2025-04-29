#ifndef HTTP_IMPL_HPP
#define HTTP_IMPL_HPP

#include <json.hpp>
#include <pqxx/pqxx>
#include <http/http_connection.h>

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
    
inline void handle_not_found(http_connection& conn) { }



}
#endif // HTTP_IMPL_HPP
