
// |--------- Geecodex -----------|
// |     Author:     @ppqwqqq     |
// |     Created At: 4 28 2025    |
// |     Version:    0.0.1        |
// | Hubei Engineering University |
// |------------------------------|

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
    using namespace geecodex::database;
    using namespace geecodex::http;
                            
    if (argc != 8) {
        std::cerr << "Usage: " << argv[0] 
                  << " <address> <port> <db_host> <db_port> <db_name> <db_user> <db_pwd> \n"
                  << "Example: " << argv[0] 
                  << " 0.0.0.0 8080 localhost 5432 geecodex ppqwqqq **********";
        return EXIT_FAILURE;
    }
                    
    connection_config config{ argv[3]
                            , static_cast<unsigned short>(std::atoi(argv[4]))
                            , argv[5]
                            , argv[6]
                            , argv[7]
                            };
    
    try {
        auto& db = pg_connection::get_instance(config);
        if (!db.is_initialized()) {
            std::cerr << "Failed to initialize database connection" << std::endl;
            return EXIT_FAILURE;
        }
        std::cout << "Database connection initialized successfully" << std::endl;

        auto const address = geecodex::http::net::ip::make_address(argv[1]);
        unsigned short port = static_cast<unsigned short>(std::atoi(argv[2]));

        net::io_context ioc{1};
        http_server server{ioc, {address, port}};
        
        std::cout << "HTTP server started at " << argv[1] << ":" << argv[2] << '\n'
                  << "Press Ctrl+C to stop the server" << '\n';
        server.run();
        ioc.run();
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
