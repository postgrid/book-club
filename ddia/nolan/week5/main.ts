interface RunLengthEncoding {
    data: Map<string, number[]>;
    rowsIngested: number;
};

const extendRunLengthEncoding = (runLengthEncoding: RunLengthEncoding, newValue: string) => {
    if (!runLengthEncoding.data.has(newValue)) {
        runLengthEncoding.data.set(
            newValue,
            [runLengthEncoding.rowsIngested]
        );
    }

    for(const [value, encounters] of runLengthEncoding.data) {
        if (value === newValue) {
            // Odd number means zero last encountered
            // Switch to ones and increment
            if (encounters.length % 2 === 0) {
                encounters.push(1);
            }

            // Even number means one last encountered
            // Increment value
            else {
                ++encounters[encounters.length - 1];
            }

            continue;
        }

        if (encounters.length % 2 === 0) {
            ++encounters[encounters.length - 1];
        } else {
            encounters.push(1);
        }

    }
    
    ++runLengthEncoding.rowsIngested;
}

const createRunLengthEncodings = <Key extends string>(
    rows: Record<Key, string>[], 
    keys: Key[],
) => {
    const runLengthEncodings = new Map<Key, RunLengthEncoding>(
        keys.map(
            (key) => [key, {
                rowsIngested: 0,
                data: new Map(),
            }]
        )
    );

    for(const row of rows) {
        for(const key of keys) {
            const runLengthEncoding = runLengthEncodings.get(key)!; 

            const value = row[key];

            extendRunLengthEncoding(runLengthEncoding, value);
        }
    }
}

const unfoldRunLengthEncoding = (runLengthEncoding: RunLengthEncoding) => {
    const values = new Array(runLengthEncoding.rowsIngested).fill(null);

    for(const [value, encounters] of runLengthEncoding.data) {
        let currentRow = 0;
        for(const [index, consecutiveCount] of encounters.entries()) {
            if (index % 2 === 1) {
                for(let i = 0; i < consecutiveCount; ++i) {
                    values[i + currentRow] = value;
                }
            }

            currentRow += consecutiveCount;
        }
    }

    return values;
}