package ecs2

MAX_QUERY_TYPES :: 16

Query :: struct {
	world:  ^World,
	n:      int,
	tids:   [MAX_QUERY_TYPES]typeid,
	pools:  [MAX_QUERY_TYPES]^Pool,
	target: int,
	idx:    int,
	entity: Entity,
	stale:  bool,
}

query_new :: proc(w: ^World, tids: []typeid) -> (q: Query) {
	q.world = w
	min_n, min_i := max(int), -1

	for tid, i in tids {
		if i >= MAX_QUERY_TYPES do break

		q.tids[i], q.n = tid, i + 1

		if idx, ok := w.pool_for[tid]; ok {
			p := w.pools[idx]
			q.pools[i] = p

			if len(p.entities) < min_n {
				min_n, min_i = len(p.entities), i
			}
		} else {
			q.stale = true
		}
	}
	q.target = min_i

	return
}

query_refresh :: proc(q: ^Query) {
	q.stale = false

	min_n, min_i := max(int), -1

	for i in 0 ..< q.n {
		if q.pools[i] == nil {
			if idx, ok := q.world.pool_for[q.tids[i]]; ok {
				q.pools[i] = q.world.pools[idx]
			}
		}

		if p := q.pools[i]; p != nil && len(p.entities) < min_n {
			min_n, min_i = len(p.entities), i
		}
	}

	q.target = min_i
}

query_reset :: proc(q: ^Query) {
	q.idx = 0
	if q.stale do query_refresh(q)
}

query_next :: proc(q: ^Query) -> bool {
	if q.stale do query_refresh(q)
	if q.target < 0 do return false

	p := q.pools[q.target]
	if p == nil do return false

	for q.idx < len(p.entities) {
		e := p.entities[q.idx]
		q.idx += 1

		matches := true
		for i in 0 ..< q.n {
			if i == q.target do continue
			pp := q.pools[i]

			if pp == nil || int(e) >= len(pp.sparse) || pp.sparse[int(e)] == -1 {
				matches = false
				break
			}
		}

		if matches {
			q.entity = e
			return true
		}
	}

	return false
}

query_get :: proc(q: ^Query, e: Entity, $T: typeid) -> ^T {
	for i in 0 ..< q.n {
		if q.tids[i] != typeid_of(T) do continue

		p := q.pools[i]
		if p == nil || int(e) >= len(p.sparse) do return nil

		di := p.sparse[int(e)]
		if di < 0 || p.stride == 0 do return nil

		return cast(^T)&p.data[di * p.stride]
	}

	return nil
}

query_first :: proc(q: ^Query) -> Maybe(Entity) {
	query_reset(q)

	if query_next(q) {
		return q.entity
	}

	return nil
}

query_collect :: proc(q: ^Query, into: ^[dynamic]Entity) {
	query_reset(q)
	for query_next(q) {
		append(into, q.entity)
	}
}
