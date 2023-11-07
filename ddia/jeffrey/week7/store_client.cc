#include <iostream>
#include <memory>
#include <string>

#include "absl/flags/flag.h"
#include "absl/flags/parse.h"
#include <grpcpp/grpcpp.h>
#include "jeffreystore.grpc.pb.h"

ABSL_FLAG(std::string, target, "localhost:50051", "Server address");

using grpc::Channel;
using grpc::ClientContext;
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

class StoreClient {
    public: StoreClient(std::shared_ptr < Channel > channel): stub_(Store::NewStub(channel)) {}

    std::string Open(const std::string & filename) {
        OpenRequest request;
        OpenResponse response;
        ClientContext context;

        request.set_filename(filename);
        Status status = stub_ -> Open( & context, request, & response);

        return response.status();
    }

    std::string GetKey(const std::string & filename,
        const std::string & key) {
        GetRequest request;
        GetResponse response;
        ClientContext context;

        request.set_filename(filename);
        request.set_key(key);

        Status status = stub_ -> GetKey( & context, request, & response);

        return response.value();
    }

    std::string SetKey(const std::string & filename,
        const std::string & key,
            const std::string & value) {
        SetRequest request;
        SetResponse response;
        ClientContext context;

        request.set_filename(filename);
        request.set_key(key);
        request.set_value(value);

        Status status = stub_ -> SetKey( & context, request, & response);

        return response.status();
    }

    std::string DeleteKey(const std::string & filename,
        const std::string & key) {
        DeleteRequest request;
        DeleteResponse response;
        ClientContext context;

        request.set_filename(filename);
        request.set_key(key);

        Status status = stub_ -> DeleteKey( & context, request, & response);

        return response.status();
    }

    private: std::unique_ptr < Store::Stub > stub_;
};

int main(int argc, char ** argv) {
    absl::ParseCommandLine(argc, argv);
    std::string target_str = absl::GetFlag(FLAGS_target);
    StoreClient store(
        grpc::CreateChannel(target_str, grpc::InsecureChannelCredentials()));

    // Make requests
    std::string filename("data");
    std::string reply = store.Open(filename);
    std::cout << "Recieved: " << reply << std::endl;

    std::string key("key");
    std::string value("value");
    reply = store.SetKey(filename, key, value);
    std::cout << "Recieved: " << reply << std::endl;

    reply = store.GetKey(filename, key);
    std::cout << "Recieved: " << reply << std::endl;

    return 0;
}