const isPlainObject = (value: any): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value);

const flatten = (value: any): any => {
    if (value === null || typeof value !== 'object') {
        return value;
    }

    if (Array.isArray(value)) {
        return value.map(flatten);
    }

    const newObj: Record<string, unknown> = {};

    for (const [key, objValue] of Object.entries(value)) {
        const flatObjValue = flatten(objValue);

        if (isPlainObject(flatObjValue)) {
            for (const [innerKey, innerObjValue] of Object.entries(
                     flatObjValue)) {
                newObj[`${key}_${innerKey}`] = innerObjValue;
            }
        } else {
            newObj[key] = flatObjValue;
        }
    }

    return newObj;
};

const liftArrays =
    (value: any, tables: Map<string, unknown[]>, tableName: string, id: number,
     parentIDKeyValue?: [string, number]) => {
        if (!isPlainObject(value)) {
            return value;
        }

        const newObj: Record<string, unknown> = {
            id,
        };

        if (parentIDKeyValue) {
            newObj[parentIDKeyValue[0]] = parentIDKeyValue[1];
        }

        for (const [key, objValue] of Object.entries(value)) {
            if (Array.isArray(objValue)) {
                tables.set(
                    key,
                    (tables.get(key) ?? [])
                        .concat(objValue.map(
                            (v, i) => liftArrays(
                                v, tables, key, i + 1,
                                [`${tableName}_id`, id]))));
            } else {
                newObj[key] = objValue;
            }
        }

        return newObj;
    };

const documentToRelational = (document: Record<string, unknown>) => {
    // Start by flattening any nested objects, so `contact_info.blog`
    // gets turned into `contact_info_blog`.
    //
    // Recurse down nested objects in pre-order so that we end
    // up with flat objects everywhere except for arrays.
    //
    // Then, move array elements to a different table and reference
    // an `id` field on the base document (set it to 1 if there
    // is no such field).

    const tables = new Map<string, unknown[]>();

    const flatDoc = flatten(document);

    const BASE_TABLE_NAME = 'base';

    const baseRelDoc = liftArrays(flatDoc, tables, BASE_TABLE_NAME, 1);

    // Base document gets inserted into a base table
    tables.set(BASE_TABLE_NAME, [baseRelDoc]);

    return tables;
};

const readings = [{
    sensorID: '1231344124',
    minute: '2022-03-23T00:01',
    values: [[{
        item_0: 0,
        item_1: 1,
        parent_id: 1,
    }]],
    total: 0,
}];

const res = documentToRelational({
    user_id: 0,
    contact_info: {
        blog: {
            link: 'https://apaar.dev',
            last_post: '2022/02/23',
        },
        twitter: '@AMadan4'
    },
    positions: [
        {
            job_title: 'Software Engineer',
            organization: 'Ubisoft',
            job_ad: [{
                link: 'https://indeed.com',
                visits: [
                    {'date': '2018/02/20'},
                    {'date': '2018/05/20'},
                ]
            }]
        },
        {
            job_title: 'Software Engineer',
            organization: 'Apple',
            job_ad: {
                link: 'https://indeed.com',
                visits: [
                    {'date': '2019/02/20'},
                    {'date': '2019/05/20'},
                    {'date': '2019/10/20'},
                ]
            },
        }
    ],
    education: [{school_name: 'University of Waterloo', start: 2016, end: 2021}]
});

console.log(res);
