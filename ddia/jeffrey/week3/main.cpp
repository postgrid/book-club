#include <fstream>
#include <iostream>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

using namespace std;

// problems include escaping characters like spaces
// if delete is the value of a key, then it's gonna get deleted

class Database {
public:
  Database() {}

  void open(const string &filename) {
    this->opened.insert(filename);
    if (this->hashindex.find(filename) == this->hashindex.end()) {
      ifstream file(filename);
      if (!file) {
        ofstream createFile(filename);
        if (!createFile) {
          cerr << "Error: Unable to create file" << endl;
          return;
        }
        createFile.close();

        file.open(filename);
        if (!file) {
          cerr << "Error: Unable to open file" << endl;
          return;
        }
      }

      string line;
      streampos position = 0;
      while (getline(file, line)) {
        istringstream lineStream(line);
        string key, value;
        if (lineStream >> key >> value) {
          this->hashindex[filename][key] = position;
        }
        position = file.tellg();
      }
      file.close();
    }
  }

  void add(const string &filename, const string &key, const string &value) {
    if (this->opened.find(filename) == this->opened.end()) {
      cerr << "Error: Open database first" << endl;
      return;
    }

    fstream file(filename, ios::in | ios::out);
    if (!file) {
      cerr << "Error: File not found" << endl;
      return;
    }

    file.seekg(0, ios::end);
    this->hashindex[filename][key] = file.tellg();
    file << key << " " << value << endl;
    file.close();
  }

  void deleteKey(const string &filename, const string &key) {
    if (this->opened.find(filename) == this->opened.end()) {
      cerr << "Error: Open database first" << endl;
      return;
    }

    fstream file(filename, ios::in | ios::out);
    if (!file) {
      cerr << "Error: File not found" << endl;
      return;
    }

    file.seekg(0, ios::end);
    this->hashindex[filename][key] = file.tellg();
    file << key << " deleted" << endl;
    file.close();
  }

  string get(const string &filename, const string &key) {
    if (this->opened.find(filename) == this->opened.end()) {
      cerr << "Error: Open database first" << endl;
      return "";
    }

    ifstream file(filename);
    if (!file) {
      cerr << "Error: File not found" << endl;
      return "";
    }

    streampos position = this->hashindex[filename][key];
    file.seekg(position);
    string line;

    getline(file, line);
    istringstream lineStream(line);
    string storedKey, value;
    if (lineStream >> storedKey >> value) {
      return value;
    }
    file.close();
    return "";
  }

  void close(const string &filename) { this->hashindex[filename].clear(); }

  void compact(const string &filename) {

    if (this->opened.find(filename) == this->opened.end()) {
      cerr << "Error: Open database first" << endl;
      return;
    }

    ifstream file(filename);
    if (!file) {
      cerr << "Error: File not found" << endl;
      return;
    }
    unordered_map<string, string> reduced;

    string line;
    while (getline(file, line)) {
      istringstream lineStream(line);
      string key, value;
      if (lineStream >> key >> value) {
        reduced[key] = value;
      }
    }
    file.close();

    fstream new_file(filename + "_compacted", ios::out);

    for (const auto &pair : reduced) {
      if (pair.second == "deleted") {
        continue;
      }
      this->hashindex[filename][pair.first] = new_file.tellg();
      new_file << pair.first << " " << pair.second << endl;
    }

    new_file.close();
    remove(filename.c_str());
    rename((filename + "_compacted").c_str(), filename.c_str());
  }

private:
  unordered_set<string> opened;
  unordered_map<string, unordered_map<string, streampos>> hashindex;
};

int main() {
  Database db;
  int running = 1;
  string command;
  string dbFile;

  while (running) {
    cin >> command >> dbFile;
    if (command == "quit") {
      running = 0;
    } else if (command == "open") {
      db.open(dbFile);
    } else if (command == "add") {
      string key, value;
      cin >> key >> value;
      db.add(dbFile, key, value);
    } else if (command == "delete") {
      string key;
      cin >> key;
      db.deleteKey(dbFile, key);
    } else if (command == "get") {
      string key;
      cin >> key;
      cout << db.get(dbFile, key) << endl;
    } else if (command == "close") {
      string key;
      cin >> key;
      db.close(dbFile);
    } else if (command == "compact") {
      db.compact(dbFile);
    }
  }
}
