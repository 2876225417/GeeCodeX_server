#ifndef LOGGER_HPP
#define LOGGER_HPP

#include <memory>
#include <iostream>

#define SPDLOG_ACTIVE_LEVEL SPDLOG_LEVEL_DEBUG
#include <spdlog/spdlog.h>
#include <spdlog/async.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/fmt/ostr.h>

namespace geecodex::logger {

inline void setup_logger() {
    try {
        spdlog::init_thread_pool(8192, 1);
        
        auto console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
        console_sink->set_level(spdlog::level::debug);
        console_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] [%t] %v");

        auto rotating_file_sink = 
            std::make_shared<spdlog::sinks::rotating_file_sink_mt>("logs/geecodex.log", 1024 * 1024 * 5, 3);
        rotating_file_sink->set_level(spdlog::level::info);
        rotating_file_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] [%t] %v");

        std::vector<spdlog::sink_ptr> sinks{ console_sink, rotating_file_sink };
        auto main_logger = std::make_shared<spdlog::async_logger>( "geecodex"
                                                                 , sinks.begin()
                                                                 , sinks.end()
                                                                 , spdlog::thread_pool()
                                                                 , spdlog::async_overflow_policy::block
                                                                 );
        main_logger->set_level(spdlog::level::debug);
        
        spdlog::set_default_logger(main_logger);
        spdlog::flush_on(spdlog::level::warn);

        SPDLOG_INFO("Logging system initialzed.");
    } catch (const spdlog::spdlog_ex& e) {
        std::cerr << "Log initialization failed: " << e.what()  << std::endl;
    }
}

}

#endif // LOGGER_HPP