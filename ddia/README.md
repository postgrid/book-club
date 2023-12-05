# Designing Data Intensive Applications

This README has the exercises for DDIA. Your solution for week N should be placed in a folder named `{your first name}/{weekN}` relative to this directory. If the week has multiple exercises, it is up to you how you want to structure that in your subfolder. A script/file per exercise is
usually sufficient but you can also have a folder for each.

## Schedule

### Week 12 (Dec 5 - Dec 12)

Read up until "Partitioning and Secondary Indexes" on page 206.

### Week 11 (Nov 28 - Dec 5)

Continue catching up on readings and assignment from last week.

### Week 10 (Nov 21 - Nov 28)

Read up until "Detecting Concurrent Writes" on page 184.

Continue the exercise from last week.

### Week 9 (Nov 14 - Nov 21)

Read up until "Handling Write Conflicts" on page 171.

1. Write a logical replication log (see page 160) for operations against your key value store.
You should probably do this in your server program. Every node will write this log.

2. Create a config file that stores which node is the leader (and how to contact it) and which nodes are
replicas.

3. Update your server to ship these writes to other running instances (or vice versa)
of your database (followers). Note that this must be done over the network. It should load the location
of these replicas from the aforementioned config file. This program is only going to run on the "leader" node.

4. Update your client to also read the config file and contact the leader for all write requests
and contact either the leader or a replica for read requests.

**BONUS** Create a program (`config-daemon`) that monitors the health of every node.

**BONUS** Add endpoints to your config-daemon to query the configuration of the network. For example, you should be able to ask
it for all the nodes and their IPs/URLs, and their current state (leader/follower). This should be used by your client to
determine who to make queries to rather than reading a config file

### Week 8 (Nov 7 - Nov 14)

Read up until "Problems with Replication Lag".

Continue on the exercise from last week.

### Week 7 (Oct 31 - Nov 7)

Read up until the end of Chapter 4.

1. Create a gRPC server/client that uses your key-value store as a library.

Should support the `set`, `get`, and `delete` operations over the network. Make
sure to document your proto files.

2. Write a gRPC client for your key-value store in a different language than
the server.

### Week 6 (Oct 24 - Oct 31)

Catch up on previous weeks exercises and readings.

### Week 5 (Oct 17 - Oct 24)

Read up until "The Merits of Schemas" on page 127.

#### Exercises

1. Read a set of CSV files and generate a custom column-oriented binary format for fast analytics.

The CSV file itself won't have any schema. The column-oriented format must be set up such that one can
quickly figure out the AVG of the "Sales" column or something (without loading up all the data into memory).

Example CSV Data:

```CSV
Date,Employee ID,Product ID,Sold Quantity
2023-10-23,1,1,100
2023-10-20,1,2,100
2023-10-21,1,1,150
```

You can imagine there are similar CSVs for the product catalog and employees.

**Bonus** Convert back from column-oriented format to CSVs.

**Bonus 2** Write a CLI that does queries on your column file.

2. For columns which have values with low-cardinality (the set of values you see in the file is less than some
percentage of the total row count) employ bitmap compression as described on page 97 and 98.

3. Write a function that can generate a data cube from your column-oriented file. See page 102 for an
example of a data cube.

The idea here is to write a function that loads your column file, takes in another function that processes these columns
and generates a new column file with preprocessed information. Up to you how you want to implement it.

### Week 4 (Oct 10 - Oct 17)

Use this week to catch up on any missed reading/exercises/bonuses from last week.

### Week 3 (Oct 3 - Oct 10)

Read up until Column-Oriented Storage on page 95.

#### Exercises

1. Write an in-process key-value store that keeps all writes/deletes in a single log and maintains an in-memory hash index. The key value store only needs to supply the functions `open(filename: string): Store`, `get(db: Store, key: string): Buffer | null`, `set(db: Store, key, value: Buffer): void`, `delete(db: Store, key: string)`, `close(db:Store): void`.

Note that the syntax above is TypeScript-ish but you can use any programming language for any of these exercises.

Also note that the log file can be stored in any format, but you must be able to store the equivalent of a NodeJS Buffer i.e. binary blobs as the values.

```ts
const db = open(“test.log”);

set(db, “a”, Buffer.from(“test”));
set(db, “b”, Buffer.from(“test 2”));

const a = get(db, “a”);

assert.equal(a.toString(), “test”);

delete(db, “a”);

close(db);

// Note that the same log is opened again (to demonstrate durability)
const db2 = open(“test.log”);

const a = get(db2, “a”);
const b = get(db2, “b”);

assert.equal(a, null);
assert.equal(b.toString(), “test 2”);
```

**Bonus** Write a function compact(filename: string, outputFilename: string) that takes in the log file and removes all redundant ops (e.g. a key that’s been set multiple times should only be present once in the resulting file, deleted keys shouldn’t be present at all).

**Bonus 2** Segment the log file once it reaches a certain size (as described in the textbook).

**Bonus 3** Write a worker/thread that compacts previously written segments and merges them.

### Week 2 (Sept 19 - Sept 26)

Read up until the end of Hash Indices on page 75.

#### Exercises

1. You’re given a graph that’s described in JSON similarly to the following relational tables

```SQL
CREATE TABLE vertices (
    vertex_id integer PRIMARY KEY,
    properties json
);

CREATE TABLE edges (
    edge_id integer PRIMARY KEY,
    tail_vertex integer REFERENCES vertices (vertex_id),
    head_vertex integer REFERENCES vertices (vertex_id),
    label text,
    properties json
);
```

You want to write a function that lets you find all the objects that have an eventual connection with some vertex. For example, the following Cypher query

```
MATCH
    (person) -[:BORN_IN]-> () -[:WITHIN*0..]-> (us:Location {name:'United States'}),
    (person) -[:LIVES_IN]-> () -[:WITHIN*0..]-> (eu:Location {name:'Europe'})
RETURN person.name
```

In this case it’s finding all the names of people who were born in the US and live in Europe.

Your function can receive the above vertices and edges arrays and also an array of labels for the edges you want to follow as well as some “type” property on the vertex like “person”, and the goal is to follow the edges until it matches another “label” that you pass along and you should collect all of those vertices.

```ts
function queryGraph(
    vertices,
    edges,
    searchForNodeType = “person”,
    connections = [
        {“label”: “born_in”, “follow”: “within”, “name”: “us”},
        {“label”: “lives_in”, “follow”: “within”, “name”: “europe”}
    ]
);
```

For our query function, always recurse (so if e.g. they have a edge “born_in” to a vertex “london” which has an edge “within” to vertex “uk”, and that has a edge “within” to vertex “europe”, that counts as having a connection `{label=”born_in”, name=”europe”}`.

**Bonus** Allow incremental traversal of the vertices (as in, your query function returns an iterable of some sort, e.g. your function could return a cursor object that has a “next” method that returns the next matching vertex).

### Week 1 (Sep 13 - Sep 19)

Read until chapter 2 but stop before "Graph-like Data Models".

#### Exercises

1. Write a function (any language) that receives a document such as the one in Example 2-1 on page 30/31 and converts this into a “relational” data model like the following:

```js
{
    "Users": [
        {
            "user_id": 251,
            "First_name": “Bill”,
        }
    ],

    "Positions": [
        {
            "position_id": 1,
            "job_title": "Co-chair",
            "organization": "Bill & Melinda Gates Foundation",
            "user_id": 251
        }
    ]
}
```

**Bonus**: Do the opposite, return all the fully joined documents.

2. Write your own css selector function that takes in some syntax to query the DOM and outputs the relevant element(s). By the way, this can just work on XML, and it doesn’t need to be in the browser (but that’s probably easiest).

Note: You are not allowed to use actual CSS selectors (unless you write a thing which compiles into a CSS selector e.g. from SQL)

**Big Bonus that will count for both exercises if you do it**:

Write a thing that takes in a DOM tree or something similar (XML tree) and then converts it into a relational-database type thing, and then allows you to query that using SQL-type syntax.

Although I would allow you to use SQLite or something, it would be cool to write your own SQL subset parser for this.
