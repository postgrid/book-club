const fs = require("fs");
const readline = require("readline");

class ColumnDB {
    constructor(file, filename) {
        this.filepath = file;
        this.filename = filename;
    }

    load() {
        // Ensure the directory exists or create it if it doesn't.
        if (!fs.existsSync(this.filename)) {
            fs.mkdirSync(this.filename, { recursive: true });
        }

        const readstream = fs.createReadStream(this.filepath);
        const lineReader = readline.createInterface({
            input: readstream,
            crlfDelay: Infinity,
        });

        let headings = "";
        let writestreams = [];

        lineReader.on("line", (line) => {
            // Create column files based on headings
            if (headings === "") {
                headings = line;
                for (const heading of line.split(",")) {
                    const writeStream = fs.createWriteStream(
                        `${this.filename}/${heading.replace(/\s+/g, "_")}.db`,
                        {
                            flags: "w",
                        }
                    );
                    writestreams.push(writeStream);
                }
                return;
            }

            // Write each coloumn into its own file
            const values = line.split(",");
            for (const [index, value] of values.entries()) {
                writestreams[index].write(value + "\n");
            }
        });

        // Wait for everything to finish
        return new Promise((resolve) => {
            lineReader.on("close", () => {
                writestreams.forEach((stream) => stream.end());
                console.log("CSV loaded...");
                resolve();
            });
        });
    }

    async query(filter, action) {
        // Checks if data satisfies the passed in filters
        const validateData = (data, filter) => {
            if (filter.all) {
                return true;
            } else if (filter.greaterThan && data > filter.greaterThan) {
                return true;
            } else if (filter.lessThan && data < filter.lessThan) {
                return true;
            } else if (filter.equal && filter.equal === data) {
                return true;
            } else if (
                filter.range &&
                filter.range[0] <= data &&
                data <= filter.range[1]
            ) {
                return true;
            } else if (filter.within && filter.within.includes(data)) {
                return true;
            }

            return false;
        };

        const iterators = [];
        const keys = Object.keys(filter);
        let res =
            action.operation === "raw"
                ? []
                : action.operation === "count"
                ? -1
                : 0;

        let targetIt;

        // Create an iterator for the target file if we want the raw data of this column
        if (action.target) {
            const targetStream = fs.createReadStream(
                `${this.filename}/${action.target.replace(/\s+/g, "_")}.db`
            );
            const targetLineReader = readline.createInterface({
                input: targetStream,
                crlfDelay: Infinity,
            });
            targetIt = targetLineReader[Symbol.asyncIterator]();
        }

        // Create iterators for files that we need when checking our filters
        for (const key of keys) {
            const rs = fs.createReadStream(
                `${this.filename}/${key.replace(/\s+/g, "_")}.db`
            );
            const rl = readline.createInterface({
                input: rs,
                crlfDelay: Infinity,
            });
            const it = rl[Symbol.asyncIterator]();
            iterators.push(it);
        }

        let read = 1;

        // All files should be same length, so we read each item and push it to the result if it satisfies the filter
        while (read) {
            let valid = true;
            const row = action.target ? await targetIt.next() : { done: false };

            // Read a line from each of our filter files
            for (const [index, it] of iterators.entries()) {
                const value =
                    keys[index] === action.operation.target
                        ? row
                        : await it.next();
                if (value.done) {
                    read = 0;
                    continue;
                }

                if (
                    Object.keys(filter).length !== 0 &&
                    !validateData(value.value, filter[keys[index]])
                ) {
                    valid = false;
                }
            }

            if (valid && !row.done) {
                if (action.operation === "raw") {
                    res.push(row.value);
                } else if (action.operation === "sum") {
                    res += parseInt(row.value);
                } else if (action.operation === "count") {
                    res++;
                }
            }
        }

        return res;
    }
}

async function main() {
    const db = new ColumnDB("data.csv", "top_secret_info");
    await db.load();

    console.log(
        await db.query(
            { Employee_ID: { equal: "1" }, Product_ID: { equal: "1" } },
            { operation: "raw", target: "Sold_Quantity" }
        )
    );

    console.log(
        await db.query({ Product_ID: { equal: "1" } }, { operation: "count" })
    );

    console.log(
        await db.query(
            { Employee_ID: { range: ["3", "6"] }, Product_ID: { equal: "1" } },
            { operation: "raw", target: "Sold_Quantity" }
        )
    );

    console.log(
        await db.query(
            {
                Employee_ID: { within: ["1", "11", "12", "23"] },
                Product_ID: { equal: "1" },
            },
            { operation: "sum", target: "Sold_Quantity" }
        )
    );

    console.log(
        await db.query(
            { Sold_Quantity: { lessThan: "250" } },
            { operation: "count" }
        )
    );

    console.log(
        await db.query(
            { Sold_Quantity: { lessThan: "250" } },
            { operation: "raw", target: "Sold_Quantity" }
        )
    );

    console.log(
        await db.query(
            { Date: { lessThan: "2023-11-21" } },
            { operation: "raw", target: "Employee_ID" }
        )
    );

    console.log(
        await db.query({ Date: { all: true } }, { operation: "count" })
    );
}

main();

/* data.csv
Date,Employee ID,Product ID,Sold Quantity
2023-09-23,1,1,100
2023-10-20,1,2,100
2023-10-21,1,1,150
2023-10-21,1,1,150
2023-11-21,2,1,150
2023-11-21,3,1,250
2023-12-21,4,1,350
2023-12-21,5,1,450
2023-12-21,6,1,550
*/
