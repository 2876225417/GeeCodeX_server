
// |--------- Geecodex -----------|
// |     Author:     @ppqwqqq     |
// |     Created At: 4 28 2025    |
// |     Version:    0.0.1        |
// | Hubei Engineering University |
// |------------------------------|

#include "spdlog/spdlog.h"
#include <csignal>
#include <database/db_ops.hpp>
#include <http/http_server.h>
#include <database/db_conn.h>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <ratio>
#include <thread>
#include <atomic>
#include <memory>
#include <vector>
#include <utils/logger.hpp>

/*** Launch Params
 *   1. Server
 *    1.1 IP Address (default: 0.0.0.0) 
 *    1.2 Port (default: 8080)
 *   2. Database
 *    2.1 Host (default: localhost)
 *    2.2 Database Port (default: 5432)
 *    2.3 Database Name
 *    2.4 Database User 
 *    2.5 Database Pwd 
 *    
 *    Run i.g.
 *    ./geecodex_server 0.0.0.0 8080 localhost 5432 db_name db_user db_pwd
 */

int main(int argc, char* argv[]) {    
    geecodex::logger::setup_logger();

    using namespace geecodex::database;
    using namespace geecodex::http;
                       
    if (argc != 8) {
        SPDLOG_ERROR("Usage: {} <address> <port> <db_host> <db_port> <db_name> <db_user> <db_pwd>", argv[0]);
        SPDLOG_ERROR("Example: {} 0.0.0.0 8080 localhost 5432 geecodex ppqwqqq **********", argv[0]);
        return EXIT_FAILURE;
    }
    
    SPDLOG_INFO("Server starting with the following arguments: ");
    for (int i = 0; i < argc; i++) SPDLOG_INFO("    argv[{}]: {}", i, argv[i]);

    connection_config config{ argv[3]
                            , static_cast<unsigned short>(std::atoi(argv[4]))
                            , argv[5]
                            , argv[6]
                            , argv[7]
                            };
    
    try {
        auto& db = pg_connection::get_instance(config);
        if (!db.is_initialized()) {
            SPDLOG_CRITICAL("Failed to initialize database connection");
            return EXIT_FAILURE;
        }
        SPDLOG_INFO("Database connection initialized successfully");

        auto const address = geecodex::http::net::ip::make_address(argv[1]);
        unsigned short port = static_cast<unsigned short>(std::atoi(argv[2]));

        net::io_context ioc{2}; // Concurrenct Hint
        http_server server{ioc, {address, port}};
        
        SPDLOG_INFO("HTTP server started at {}:{}", argv[1], argv[2]);
        SPDLOG_INFO("Press Ctrl+C to stop the server");
        
        server.run();
        ioc.run();

        SPDLOG_INFO("Server shutdown gracefully.");
    } catch (const std::exception& e) {
        SPDLOG_CRITICAL("Unhandled exception in main: {}", e.what());
        return EXIT_FAILURE;
    }

    spdlog::shutdown();
    return EXIT_SUCCESS;
}
