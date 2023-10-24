type Doc = Record<string, any> & { id : string };
type Collection = Map<string, Doc>;
type DocumentDB = Map<string, Collection>;

const makeCollection = () => new Map<string, Doc>() as Collection;
const makeDocumentDB = () => new Map<string, Collection>() as DocumentDB;

type Primitive = string | number | bigint | boolean | null;
type Row = Record<string, Primitive> & { id: number };
type Table = Map<number, Row>;
type RelationalDB = Map<string, Table>;

const makeTable = () => new Map<number, Row>() as Table;
const makeRelationalDB = () => new Map<string, Table>() as RelationalDB;

const isPrimitive = (v: any) =>
    typeof v === 'string' 
    || typeof v === 'number' 
    || typeof v === 'boolean'
    || typeof v === 'bigint'
    || typeof v === 'undefined'
    || v === null;

const isRecord = (v: any) =>
    typeof v === 'object'
    && v !== null
    && !Array.isArray(v);

const documentChars = 'abcdefghijklmnopqrstuvwxyz1234567890';
const generateDocumentID = (collectionName: string) =>
    `${collectionName}_${
        new Array(13).fill('a').map(() => documentChars.charAt(
            Math.floor(documentChars.length * Math.random())
        ))
    }`;

const generateRelationalID = (table: Table) => {
    let maxKey = 0;
    for(const key of table.keys()) {
        if (key > maxKey) {
            maxKey = key;
        }
    }

    return maxKey + 1;
}

const extendTablesByDocument = (
    document: Doc,
    collectionName: string,
    tables: RelationalDB,
    parentKey?: number,
    parentCollectionName?: string
) => {
    const currentTable = tables.get(collectionName) ??
        makeTable();
    tables.set(collectionName, currentTable);

        
    const documentEntries = Object.entries(document);
        
    const primitiveEntries: [string, Primitive][] = documentEntries.filter(([key, value]) => isPrimitive(value) && key !== 'id');
    
    const rowKey = generateRelationalID(currentTable);
    const row: Row = {
        id: rowKey,
        ...Object.fromEntries(primitiveEntries),
    }

    if (parentCollectionName && parentKey) {
        row[`${parentCollectionName}_id`] = parentKey;
    }

    currentTable.set(rowKey, row);


    const arrayEntries: [string, any[]][] = documentEntries.filter(([_key, value]) => Array.isArray(value));
    for(const [arrayFieldName, array] of arrayEntries) {
        for(const value of array) {
            extendTablesByDocument(
               isRecord(value) 
                ? value 
                : Array.isArray(value)
                    ? Object.fromEntries(
                        value.map((v, index) => [`${arrayFieldName}_${index}`, v])
                    )
                    : { value },
               arrayFieldName,
               tables,
               rowKey,
               collectionName
            );
        }
    }

    const subObjectEntries: [string, any][] = documentEntries.filter(([_key, value]) => isRecord(value));
    for(const [fieldName, subObject] of subObjectEntries) {
        extendTablesByDocument(
            subObject,
            fieldName,
            tables,
            rowKey,
            collectionName
        );
    }
}

const convertDocuments = (collections: DocumentDB) => {
    const tables = makeRelationalDB();
    
    for(const [collectionName, collection] of collections) {
        for(const [_documentID, document] of collection) {
            extendTablesByDocument(
                document,
                collectionName,
                tables,
            )
        }
    }

    return tables;
}

const testCollections: DocumentDB = new Map([
    ['letter', new Map([
        ['letter_abc', {
            id: 'letter_abc',
            description: 'Cool letter abc',
            metadata: {
                sales: {
                    price: 230,
                    leadType: 'Good'
                },
                methods: [
                    'email', 'phone', 'telegraph'
                ]
            },
            to: {
                firstName: 'John',
                line1: '123 Wallaby Way'
            }
        }],
        ['letter_xyz', {
            id: 'letter_xyz'
        }]
    ])],
    ['postcard', new Map([
        ['postcard_abc', {
            id: 'postcard_abc'
        }],
        ['postcard_xyz', {
            id: 'postcard_xyz'
        }]
    ])]
]);

const tables = convertDocuments(testCollections);

for(const [tableName, table] of tables) {
    console.log(tableName);
    console.table([
        ...table
    ].map(([_id, row]) => row));
}
