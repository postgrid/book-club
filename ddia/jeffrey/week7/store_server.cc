#include <iostream>
#include <memory>
#include <string>
#include <fstream>
#include <iostream>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

#include "absl/flags/flag.h"
#include "absl/flags/parse.h"
#include "absl/strings/str_format.h"
#include <grpcpp/ext/proto_server_reflection_plugin.h>
#include <grpcpp/grpcpp.h>
#include <grpcpp/health_check_service_interface.h>
#include "jeffreystore.grpc.pb.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using jeffreystore::Store;
using jeffreystore::OpenRequest;
using jeffreystore::OpenResponse;
using jeffreystore::GetRequest;
using jeffreystore::GetResponse;
using jeffreystore::SetRequest;
using jeffreystore::SetResponse;
using jeffreystore::DeleteRequest;
using jeffreystore::DeleteResponse;

ABSL_FLAG(uint16_t, port, 50051, "Server port for the service");

// Logic and data behind the server's behavior.
class StoreServiceImpl final: public Store::Service {
    public: Status Open(ServerContext * context,
        const OpenRequest * request,
            OpenResponse * reply) {

        this -> opened.insert(request -> filename());
        if (this -> hashindex.find(request -> filename()) == this -> hashindex.end()) {
            std::ifstream file(request -> filename());
            if (!file) {
                std::ofstream createFile(request -> filename());
                createFile.close();
                file.open(request -> filename());
            }

            std::string line;
            std::streampos position = 0;
            while (std::getline(file, line)) {
                std::istringstream lineStream(line);
                std::string key, value;
                if (lineStream >> key >> value) {
                    this -> hashindex[request -> filename()][key] = position;
                }
                position = file.tellg();
            }
            file.close();
        }

        reply -> set_status("ok");
        return Status::OK;
    }

    Status GetKey(ServerContext * context,
        const GetRequest * request,
            GetResponse * reply) {

        if (this -> opened.find(request -> filename()) == this -> opened.end()) {
            reply -> set_status("not ok");
            reply -> set_value("");
            return Status::OK;
        }

        std::ifstream file(request -> filename());
        std::streampos position = this -> hashindex[request -> filename()][request -> key()];
        file.seekg(position);
        std::string line;

        std::getline(file, line);
        std::istringstream lineStream(line);
        std::string storedKey, value;
        if (lineStream >> storedKey >> value) {
            reply -> set_status("ok");
            reply -> set_value(value);
            return Status::OK;
        }
        file.close();

        reply -> set_value("");
        reply -> set_status("ok");
        return Status::OK;
    }

    Status SetKey(ServerContext * context,
        const SetRequest * request,
            SetResponse * reply) {

        if (this -> opened.find(request -> filename()) == this -> opened.end()) {
            reply -> set_status("not ok");
            return Status::OK;
        }

        std::fstream file(request -> filename(), std::ios::in | std::ios::out);

        file.seekg(0, std::ios::end);
        this -> hashindex[request -> filename()][request -> key()] = file.tellg();
        file << request -> key() << " " << request -> value() << std::endl;
        file.close();

        reply -> set_status("ok");
        return Status::OK;
    }

    Status DeleteKey(ServerContext * context,
        const DeleteRequest * request,
            DeleteResponse * reply) {

        if (this -> opened.find(request -> filename()) == this -> opened.end()) {
            reply -> set_status("not ok");
            return Status::OK;
        }

        std::fstream file(request -> filename(), std::ios::in | std::ios::out);

        file.seekg(0, std::ios::end);
        this -> hashindex[request -> filename()][request -> key()] = file.tellg();
        file << request -> key() << " deleted" << std::endl;
        file.close();

        reply -> set_status("ok");
        return Status::OK;
    }

    Status Compact(ServerContext * context,
        const DeleteRequest * request,
            DeleteResponse * reply) {

        if (this -> opened.find(request -> filename()) == this -> opened.end()) {
            reply -> set_status("not ok");
            return Status::OK;
        }

        std::ifstream file(request -> filename());
        std::unordered_map < std::string, std::string > reduced;

        std::string line;
        while (std::getline(file, line)) {
            std::istringstream lineStream(line);
            std::string key, value;
            if (lineStream >> key >> value) {
                reduced[key] = value;
            }
        }
        file.close();

        std::fstream new_file(request -> filename() + "_compacted", std::ios::out);

        for (const auto & pair: reduced) {
            if (pair.second == "deleted") {
                continue;
            }
            this -> hashindex[request -> filename()][pair.first] = new_file.tellg();
            new_file << pair.first << " " << pair.second << std::endl;
        }

        new_file.close();
        remove(request -> filename().c_str());
        rename((request -> filename() + "_compacted").c_str(), request -> filename().c_str());
        reply -> set_status("ok");
        return Status::OK;
    }
    private: std::unordered_set < std::string > opened;
    std::unordered_map < std::string,
    std::unordered_map < std::string,
    std::streampos >> hashindex;

};

// magic
void RunServer(uint16_t port) {
    std::string server_address = absl::StrFormat("0.0.0.0:%d", port);
    StoreServiceImpl service;

    grpc::EnableDefaultHealthCheckService(true);
    grpc::reflection::InitProtoReflectionServerBuilderPlugin();
    ServerBuilder builder;
    // Listen on the given address without any authentication mechanism.
    builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
    // Register "service" as the instance through which we'll communicate with
    // clients. In this case it corresponds to an *synchronous* service.
    builder.RegisterService( & service);
    // Finally assemble the server.
    std::unique_ptr < Server > server(builder.BuildAndStart());
    std::cout << "Server listening on " << server_address << std::endl;

    // Wait for the server to shutdown. Note that some other thread must be
    // responsible for shutting down the server for this call to ever return.
    server -> Wait();
}

int main(int argc, char ** argv) {
    absl::ParseCommandLine(argc, argv);
    RunServer(absl::GetFlag(FLAGS_port));
    return 0;
}