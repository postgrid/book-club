TEST_GRAPH = {
    'vertices': [
        {
            'id': 1,
            'type': 'person',
            'name': 'Apaar',
        },
        {
            'id': 2,
            'type': 'country',
            'name': 'India',
        },
        {
            'id': 3,
            'type': 'city',
            'name': 'Ludhiana',
        },
        {
            'id': 4,
            'type': 'state',
            'name': 'Punjab',
        },
        {
            'id': 5,
            'type': 'city',
            'name': 'Markham'
        },
        {
            'id': 6,
            'type': 'state',
            'name': 'Ontario'
        },
        {
            'id': 7,
            'type': 'country',
            'name': 'Canada'
        },
        {
            'id': 8,
            'type': 'city',
            'name': 'Sudbury'
        },
        {
            'id': 9,
            'type': 'person',
            'name': 'Nolan'
        },
        {
            'id': 10,
            'type': 'city',
            'name': 'Toronto'
        },
        {
            'id': 11,
            'type': 'airport',
            'name': 'YTZ'
        },
        {
            'id': 12,
            'type': 'airport',
            'name': 'YYZ'
        }
    ],
    
    'edges': [
        {
            'id': 1,
            'head_vertex': 1,
            'tail_vertex': 3,
            'label': 'born_in'
        },
        {
            'id': 2,
            'head_vertex': 3,
            'tail_vertex': 4,
            'label': 'within'
        },
        {
            'id': 3,
            'head_vertex': 4,
            'tail_vertex': 2,
            'label': 'within'
        },
        {
            'id': 4,
            'head_vertex': 5,
            'tail_vertex': 6,
            'label': 'within'
        },
        {
            'id': 5,
            'head_vertex': 6,
            'tail_vertex': 7,
            'label': 'within'
        },
        {
            'id': 6,
            'head_vertex': 8,
            'tail_vertex': 6,
            'label': 'within'
        },
        {
            'id': 7,
            'head_vertex': 9,
            'tail_vertex': 8,
            'label': 'born_in'
        },
        {
            'id': 8,
            'head_vertex': 1,
            'tail_vertex': 5,
            'label': 'lives_in'
        },
        {
            'id': 9,
            'head_vertex': 9,
            'tail_vertex': 8,
            'label': 'lives_in'
        },
        {
            'id': 10,
            'head_vertex': 11,
            'tail_vertex': 8,
            'label': 'has_flight_to'
        },
        {
            'id': 11,
            'head_vertex': 11,
            'tail_vertex': 10,
            'label': 'located_in'
        },
        {
            'id': 12,
            'head_vertex': 10,
            'tail_vertex': 6,
            'label': 'within'
        },
    ]
}

def iter_vertices_by_type(graph, type_):
    yield from (
        v for v in graph['vertices'] if v['type'] == type_
    )

def has_connection(graph, head_vertex_id, start_edge_label, follow_edge_label, name): 
    cur_label = start_edge_label

    seen_vertex_ids = set()
    vertex_ids = [head_vertex_id]
 
    while vertex_ids:  
        vertex_id = vertex_ids.pop()

        if vertex_id in seen_vertex_ids:
            continue
        
        vertex = next(
            v for v in graph['vertices']
            if v['id'] == vertex_id
        )

        if vertex['name'] == name:
            return True

        seen_vertex_ids.add(vertex_id)

        for edge in graph['edges']:
            if edge['label'] != cur_label:
                continue
                
            if edge['head_vertex'] != vertex_id:
                continue

            vertex_ids.append(edge['tail_vertex'])

        cur_label = follow_edge_label

    return False

def query_graph(graph, search_for_vertex_type, connections):
    for vertex in iter_vertices_by_type(graph, search_for_vertex_type):
        if all(has_connection(graph, vertex['id'], *args) for args in connections):
            yield vertex

if __name__ == '__main__':
    matches = [
        v for v in query_graph(
            TEST_GRAPH,
            'airport',
            (
                ('located_in', 'within', 'Ontario'),
                ('has_flight_to', 'within', 'Ontario'),
            )
        )
    ]

    print(matches)
