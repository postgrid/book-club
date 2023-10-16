# Designing Data Intensive Applications

This README has the exercises for DDIA. Your solution for week N should be placed in a folder named `{your first name}/{weekN}` relative to this directory. If the week has multiple exercises, it is up to you how you want to structure that in your subfolder. A script/file per exercise is
usually sufficient but you can also have a folder for each.

## Schedule

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
