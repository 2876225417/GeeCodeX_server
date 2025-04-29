

#include <database/db_ops.hpp>

#include <chrono>
#include <cstdlib>
#include <http/http_server.h>
#include <database/db_conn.h>
#include <iostream>
#include <thread>
#include <atomic>
#include <memory>
#include <vector>



int main(int argc, char* argv[]) {        
    using namespace inf_qwq::database;
    using namespace inf_qwq::http;
    
    connection_config config{"localhost", 5432, "geecodex", "ppqwqqq", "20041025"};

    try {
        auto& db = pg_connection::get_instance(config);
        if (!db.is_initialized()) {
            std::cerr << "Failed to initialize database connection" << std::endl;
            return EXIT_FAILURE;
        }
        std::cout << "Database connection initialized successfully" << std::endl;

        if (argc != 3) {
            std::cerr << "Usage: " << argv[0] << " <address> <port>\n";
            std::cerr << "Example:\n";
            std::cerr << "    " << argv[0] << " 0.0.0.0 8080\n";
            return EXIT_FAILURE;
        }

        auto const address = inf_qwq::http::net::ip::make_address(argv[1]);
        unsigned short port = static_cast<unsigned short>(std::atoi(argv[2]));


        inf_qwq::http::net::io_context ioc{1};
        inf_qwq::http::http_server server{ioc, {address, port}};
        server.run();
        
        std::thread http_thread([&ioc]() {
            try {
                ioc.run();
            } catch (const std::exception& e) {
                std::cerr << "HTTP server error: " << e.what() << std::endl;
            }
        });

        std::cout << "Stopping all services..." << std::endl;
        ioc.stop();
        
        if (http_thread.joinable()) {
            http_thread.join();
        }

        std::cout << "All services stopped. Exiting." << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
