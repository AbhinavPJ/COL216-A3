#!/usr/bin/env python3
import sys
import subprocess
from pathlib import Path
from collections import deque

TESTS = [
    "test_small.txt",
    "test_chain.txt",
    "test_star.txt",
    "test_disconnected.txt",
    "test_binary_tree.txt",
    "test_duplicate_edges.txt",
    "test_cycle.txt",
    "test_two_components.txt",
]


def run(cmd, cwd=None, timeout=120):
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def load_graph(path):
    with open(path, "r", encoding="utf-8") as f:
        n = int(f.readline().strip())
        adj = []
        for _ in range(n):
            vals = list(map(int, f.readline().split()))
            deg = vals[0]
            nbrs = vals[1:]
            if deg != len(nbrs):
                raise ValueError(f"Degree mismatch in {path}")
            adj.append(nbrs)
    return adj


def bfs_expected(adj, source):
    dist = [-1] * len(adj)
    dist[source] = 0
    q = deque([source])
    seen = 1

    while q:
        v = q.popleft()
        for u in adj[v]:
            if dist[u] == -1:
                dist[u] = dist[v] + 1
                q.append(u)
                seen += 1

    return seen, dist


def compile_driver(sub):
    code = r"""
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "graph.h"

int main(int argc, char** argv) {
    if (argc != 4) return 1;

    const char* impl = argv[1];
    const char* graph_path = argv[2];
    int source = atoi(argv[3]);

    Graph* g = load_graph(graph_path);
    if (!g) return 2;

    int* dist = (int*)malloc((size_t)g->num_vertices * sizeof(int));
    if (!dist) return 3;

    int visited = -1;

    if (strcmp(impl, "pointer") == 0) {
        visited = bfs_pointer(g, source, dist);
    } else if (strcmp(impl, "csr") == 0) {
        CSRGraph* csr = convert_to_csr(g);
        if (!csr) return 4;
        visited = bfs_csr(csr, source, dist);
        free_csr(csr);
    } else {
        return 5;
    }

    printf("visited=%d\n", visited);
    for (int i = 0; i < g->num_vertices; i++) {
        if (i) printf(" ");
        printf("%d", dist[i]);
    }
    printf("\n");

    free(dist);
    free_graph(g);
    return 0;
}
"""
    p = sub / "src" / "driver_check.c"
    p.write_text(code, encoding="utf-8")

    return run(
        [
            "gcc",
            "-O2",
            "-std=gnu11",
            "-Wall",
            "-Wextra",
            "-pedantic",
            "-Iinclude",
            "src/graph_loader.c",
            "src/bfs_pointer.c",
            "src/graph_csr.c",
            "src/bfs_csr.c",
            "src/driver_check.c",
            "-o",
            "driver_check",
        ],
        cwd=sub,
        timeout=240,
    )


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 visible_checker.py /path/to/submission")
        sys.exit(1)

    sub = Path(sys.argv[1]).resolve()

    print("== Build ==")
    run(["make", "clean"], cwd=sub)
    b = run(["make"], cwd=sub, timeout=240)
    if b.returncode != 0:
        print("Build failed")
        print(b.stdout + b.stderr)
        sys.exit(1)

    print("Build ok")

    d = compile_driver(sub)
    if d.returncode != 0:
        print("driver build failed")
        print(d.stdout + d.stderr)
        sys.exit(1)

    print("\n== Visible BFS tests ==")
    for test in TESTS:
        graph = sub / "tests" / test
        adj = load_graph(graph)
        exp_seen, exp_dist = bfs_expected(adj, 0)

        for impl in ("pointer", "csr"):
            r = run(["./driver_check", impl, str(graph), "0"], cwd=sub, timeout=120)

            ok = False
            if r.returncode == 0:
                lines = [x.strip() for x in r.stdout.strip().splitlines() if x.strip()]
                if len(lines) == 2 and lines[0].startswith("visited="):
                    seen = int(lines[0].split("=")[1])
                    dist = list(map(int, lines[1].split()))
                    ok = (seen == exp_seen and dist == exp_dist)

            print(f"{impl:7s} {test:24s}: {'ok' if ok else 'FAIL'}")


if __name__ == "__main__":
    main()
