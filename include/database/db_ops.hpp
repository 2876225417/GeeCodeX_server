#ifndef DB_OPS_HPP
#define DB_OPS_HPP

#include <database/db_conn.h>
#include <exception>
#include <functional>
#include <string>
#include <utility>
#include <vector>
#include <type_traits>

#include <pqxx/internal/statement_parameters.hxx>

 

namespace inf_qwq::database {
    inline int execute_non_query(const std::string& sql) {
        try {
            auto& conn = pg_connection::get_instance();
            if (!conn.is_initialized()) 
                throw database_exception(std::string("Database connection not initialized"));
            pqxx::work txn(conn.get_connection());
            pqxx::result result = txn.exec(sql);
            txn.commit();
            return result.affected_rows();
        } catch (const pqxx::sql_error& e) {
            throw database_exception("SQL error: " + std::string(e.what()) 
                                                    + ", Query: " + e.query());
        } catch (const std::exception& e) {
            throw database_exception(std::string("Exception error: " + std::string(e.what())));
        }
    }

    inline pqxx::result execute_query(const std::string& sql) {
        try {
            auto& conn = pg_connection::get_instance();
            if (!conn.is_initialized()) 
                throw database_exception(std::string("Database connection not initialized"));
            pqxx::work txn(conn.get_connection());
            pqxx::result result = txn.exec(sql);
            txn.commit();
            return result;
        } catch (const pqxx::sql_error& e) {
            throw database_exception( "SQL error: " + std::string(e.what()) 
                                                     + ", Query: " + e.query());
        } catch (const std::exception& e) {
            throw database_exception(std::string("Exception error: " + std::string(e.what())));
        }
    }

    template <typename... Args>
    inline pqxx::result execute_params( const std::string& sql
                                      , Args&&... args
                                      ) {
        try {
            auto& conn = pg_connection::get_instance();
            if (!conn.is_initialized()) 
                throw database_exception(std::string("Database connection not initialized"));
            pqxx::work txn(conn.get_connection());
            pqxx::result result = txn.exec_params(sql, std::forward<Args>(args)...);
            txn.commit();
            return result;
        } catch (const pqxx::sql_error& e) {
            throw database_exception("SQL error: " + std::string(e.what()) 
                                    + ", Query: " + e.query());
        } catch (const std::exception& e) {
            throw database_exception("Parameterized query error: " + std::string(e.what()));
        }
    }

    inline void
    execute_transaction(const std::function<void(pqxx::work&)>& transaction_func) {
        try {
            auto& conn = pg_connection::get_instance();
            if (!conn.is_initialized()) 
                throw database_exception(std::string("Database connection not initialized"));
            pqxx::work txn(conn.get_connection());
            transaction_func(txn);
            txn.commit();
        } catch (const pqxx::sql_error& e) {
            throw database_exception("Transaction SQL error: " + std::string(e.what()) 
                                    +  ", Query: " + e.query());
        } catch (const std::exception& e) {
            throw database_exception("Transaction error: " + std::string(e.what()));
        }
    }

    template <typename Container>
    inline int
    batch_insert( const std::string& table
                , const std::vector<std::string>& columns
                , const Container& data
                ){
        try {
            auto& conn = pg_connection::get_instance();
            if (!conn.is_initialized())
                throw database_exception(std::string("Database connection not initialized"));
            pqxx::work txn(conn.get_connection());

            std::string column_list;
            for (size_t i = 0; i < columns.size(); ++i) {
                if (i > 0) column_list += ", ";
                column_list += txn.quote_name(columns[i]);
            }
            
            std::string placeholders;
            for (size_t i = 0; i < columns.size(); ++i) {
                if (i > 0) placeholders += ", ";
                placeholders += "$" + std::to_string(i + 1);
            }

            std::string insert_sql = "INSERT INTO " + txn.quote_name(table) 
                                   + " (" + column_list + ") VALUES (" + placeholders +")";
            
            int affected_rows = 0;
            for (const auto& row: data) {
                pqxx::result r = txn.exec_params(insert_sql, row);
                affected_rows += r.affected_rows();
            }
            txn.commit();
            return affected_rows;
        } catch (const pqxx::sql_error& e) {
            throw database_exception("Batch insert SQL error: " + std::string(e.what()) 
                                    +  ", Query: " + e.query());
        } catch (const std::exception& e) {
            throw database_exception("Exception error: " + std::string(e.what()));
        }
    }       

    inline bool table_exists(const std::string& table_name) {
        try {
            auto& conn = pg_connection::get_instance();
            if (!conn.is_initialized()) 
                throw database_exception(std::string("Database connection not initialized"));
            pqxx::work txn{conn.get_connection()};
            pqxx::result result = txn.exec(
                "SELECT EXISTS (SELECT 1 FROM information_schema.tables) "
                "WHERE table_schema = 'public' AND table_name = " + txn.quote(table_name) + ")"
            );
            txn.commit();
            return result[0][0].as<bool>();
        } catch (const std::exception& e) {
            throw database_exception("Error checking table existence: " + std::string(e.what()));
        }
    }

    template <typename T>
    inline T get_scalar(const std::string& sql) {
        try {
            auto& conn = pg_connection::get_instance();
            if (!conn.is_initialized()) 
                throw database_exception(std::string("Database connection not initialized"));
            
            pqxx::work txn{conn.get_connection()};
            pqxx::row row = txn.exec1(sql);
            txn.commit();
            return row[0].as<T>();
        } catch (const pqxx::sql_error& e) {
            throw database_exception("SQL error: " + std::string(e.what()) + ", Query: " + e.query());
        } catch (const std::exception& e) {
            throw database_exception("Error getting scalar value: " + std::string(e.what()));
        }
    }
}

#endif // DB_OPS_HPP
