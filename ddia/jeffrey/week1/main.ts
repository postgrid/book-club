const doc = {
    user_id: 251,
    first_name: "Bill",
    last_name: "Gates",
    summary: "Co-chair of the Bill & Melinda Gates... Active blogger.",
    region_id: "us:91",
    industry_id: 131,
    photo_url: "/p/7/000/253/05b/308dd6e.jpg",
    positions: [
        {
            job_title: "Co-chair",
            organization: "Bill & Melinda Gates Foundation",
        },
        { job_title: "Co-founder, Chairman", organization: "Microsoft" },
    ],
    education: [
        { school_name: "Harvard University", start: 1973, end: 1975 },
        { school_name: "Lakeside School, Seattle", start: null, end: null },
    ],
    contact_info: {
        blog: "http://thegatesnotes.com",
        twitter: "http://twitter.com/BillGates",
        phone_number: [
            {
                type: "cell",
                value: "911",
            },
            {
                type: "home",
                value: "905-911",
            },
        ],
    },
};

const ignoreList = ["start", "end"];

const relationalTable = {};
const createTable = (obj, table) => {
    const row = {};
    let ID = Math.floor(Math.random() * 1000000);
    for (const key of Object.keys(obj)) {
        if (ignoreList.includes(key)) {
            return;
        }

        if (typeof obj[key] === "string" || typeof obj[key] === "number") {
            row[key] = obj[key];
        } else if (Array.isArray(obj[key])) {
            for (const item of obj[key]) {
                createTable(
                    {
                        ...item,
                        [`${table}_id`]: obj[`${table}_id`],
                        [`${key}_id`]: ID,
                    },
                    key
                );
                ID = Math.floor(Math.random() * 1000000);
            }
        } else if (typeof obj[key] === "object") {
            createTable(
                {
                    ...obj[key],
                    [`${table}_id`]: obj[`${table}_id`],
                    [`${key}_id`]: ID,
                },
                key
            );
        }
    }

    if (!relationalTable[table]) {
        relationalTable[table] = [];
    }

    relationalTable[table].push(row);
};

createTable(doc, "users");
console.log(relationalTable);
