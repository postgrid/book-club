interface Bitmap {
    data: Map<string, number[]>;
    rowsIngested: number;
};

const extendBitmap = (bitmap: Bitmap, newValue: string) => {
    if (!bitmap.data.has(newValue)) {
        bitmap.data.set(
            newValue,
            [bitmap.rowsIngested]
        );
    }

    for(const [value, encounters] of bitmap.data) {
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
}

const createBitmaps = <Key extends string>(
    rows: Record<Key, string>[], 
    keys: Key[],
) => {
    const bitmaps = new Map<Key, Bitmap>(
        keys.map(
            (key) => [key, {
                rowsIngested: 0,
                data: new Map(),
            }]
        )
    );

    for(const row of rows) {
        for(const key of keys) {
            const bitmap = bitmaps.get(key)!; 

            const value = row[key];

            extendBitmap(bitmap, value);
        }
    }
}

const unfoldBitmap = (bitmap: Bitmap) => {
    const values = new Array(bitmap.rowsIngested).fill(null);

    for(const [value, encounters] of bitmap.data) {
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