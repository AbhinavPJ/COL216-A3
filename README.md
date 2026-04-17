# Cache-Friendly Graph Processing

## BFS over Pointer Graphs vs CSR Graphs

Modern processors are extremely fast at arithmetic, but **memory access
patterns** often dominate real program performance. Programs that jump
around memory unpredictably tend to suffer from poor cache behavior.

In this assignment you will explore this effect by implementing the
**same BFS algorithm over two different graph memory layouts**:

1.  Pointer-based adjacency list graph
2.  Cache-friendly CSR (Compressed Sparse Row) graph

You will then **benchmark and profile** the two implementations to
understand how **data layout affects performance**.

------------------------------------------------------------------------

# Learning Objectives

By completing this assignment you should be able to:

-   Implement **Breadth-First Search (BFS)** over multiple graph layouts
-   Convert an adjacency-list graph into **CSR format**
-   Understand **memory locality and cache effects**
-   Use **Cachegrind** to measure cache behavior
-   Analyze performance differences caused by **data structure design**

This assignment demonstrates an important systems principle:

> Algorithm complexity alone does not determine performance.\
> Memory layout and hardware interaction matter just as much.

------------------------------------------------------------------------

# Overview of the Assignment

You will implement BFS for two graph representations.

### Representation 1 --- Pointer Graph

Each vertex stores a linked list of neighbors.

Advantages: - Simple to implement - Flexible

Disadvantages: - Poor cache locality - Pointer chasing - Many heap
allocations

------------------------------------------------------------------------

### Representation 2 --- CSR Graph

CSR stores the graph in two contiguous arrays.

    row_ptr: [0, 2, 5, 7, ...]
    col_idx: [1,2,3,4,5, ...]

Advantages:

-   Compact representation
-   Sequential memory traversal
-   Much better cache locality

CSR is widely used in:

-   sparse matrix libraries
-   graph analytics frameworks
-   GPU graph processing

------------------------------------------------------------------------

# Graph Input Format

Graphs use a simple adjacency-list text format.

    n
    deg v1 v2 ... v_deg
    deg v1 v2 ... v_deg
    ...

Where:

-   `n` = number of vertices
-   each following line describes outgoing neighbors

Example:

    3
    2 1 2
    1 2
    0

Meaning:

-   vertex 0 → {1,2}
-   vertex 1 → {2}
-   vertex 2 → {}

------------------------------------------------------------------------

# Implementation Tasks

You must complete **three functions**.

All required files are already provided in `src/`.

## Task 1 --- BFS on Pointer Graph

File:

    src/bfs_pointer.c

Implement:

    int bfs_pointer(Graph* g, int source, int* dist)

Requirements:

-   Perform standard BFS
-   `dist[v]` should contain the shortest distance from `source`
-   Unreachable vertices should remain `-1`
-   Return the number of visited vertices

Pseudo-algorithm:

    initialize queue
    dist[source] = 0
    push source

    while queue not empty
        v = pop
        for each neighbor u
            if dist[u] == -1
                dist[u] = dist[v] + 1
                push u

------------------------------------------------------------------------

## Task 2 --- Convert Graph to CSR

File:

    src/graph_csr.c

Implement:

    CSRGraph* convert_to_csr(Graph* g)

CSR contains:

    row_ptr  size = n + 1
    col_idx  size = m

Where:

    row_ptr[v]   = start index of v's neighbors
    row_ptr[v+1] = end index

Example:

Adjacency lists:

    0 → 1 2
    1 → 2
    2 →

CSR:

    row_ptr = [0,2,3,3]
    col_idx = [1,2,2]

You must:

1.  count edges
2.  allocate arrays
3.  fill `row_ptr`
4.  fill `col_idx`

------------------------------------------------------------------------

## Task 3 --- BFS on CSR Graph

File:

    src/bfs_csr.c

Implement:

    int bfs_csr(CSRGraph* g, int source, int* dist)

Traversal becomes:

    for i = row_ptr[v] .. row_ptr[v+1]-1
        u = col_idx[i]

The BFS algorithm itself is identical.

------------------------------------------------------------------------

# Building the Project

Run:

    make

This produces the executable:

    graph_bench

------------------------------------------------------------------------

# Example CLI Usage

Run BFS using the pointer representation:

    ./graph_bench --impl=pointer --graph=tests/test_small.txt --source=0

Run BFS using CSR:

    ./graph_bench --impl=csr --graph=tests/test_small.txt --source=0

Run with repeated trials for benchmarking:

    ./graph_bench --impl=csr --graph=tests/test_small.txt --source=0 --repeat=10

Example output:

    visited=7 time_ms=0.14

------------------------------------------------------------------------

# Generating Larger Graphs

Example:

    python3 scripts/gen_graph.py --kind er --n 10000 --deg 8 --seed 1 --out data/test.txt

Then benchmark:

    ./graph_bench --impl=pointer --graph=data/test.txt --source=0 --repeat=5
    ./graph_bench --impl=csr --graph=data/test.txt --source=0 --repeat=5

------------------------------------------------------------------------

# Profiling with Cachegrind

Run Cachegrind:

    valgrind --tool=cachegrind ./graph_bench --impl=pointer --graph=data/test.txt --source=0

Compare with:

    valgrind --tool=cachegrind ./graph_bench --impl=csr --graph=data/test.txt --source=0

Look at:

-   `D1 misses`
-   `LLd misses`

------------------------------------------------------------------------

# Performance Report

Submit a short **1--2 page report** answering the following questions.

### Question 1 --- Runtime Comparison

Compare runtime of:

-   pointer BFS
-   CSR BFS

Which implementation is faster? By how much?

------------------------------------------------------------------------

### Question 2 --- Cache Behavior

Using Cachegrind, compare:

-   D1 cache misses
-   LLd cache misses

Which implementation generates fewer misses? Why?

------------------------------------------------------------------------

### Question 3 --- Memory Layout Explanation

Explain **why CSR tends to perform better** than pointer graphs.

Discuss:

-   spatial locality
-   contiguous arrays
-   pointer chasing

------------------------------------------------------------------------

### Question 4 --- Varying Cache Parameters

Cachegrind allows you to simulate different cache configurations.

Run experiments varying:

-   **Cache size**
-   **Associativity**
-   **Cache line size**

Example:

    valgrind --tool=cachegrind --D1=16384,4,64 ./graph_bench ...
    valgrind --tool=cachegrind --D1=32768,8,64 ./graph_bench ...

Answer the following:

1.  How does increasing **cache size** affect BFS performance?
2.  How does increasing **associativity** affect the results?
3.  How does changing **line size** influence performance?
4.  Does CSR benefit more from larger cache lines than pointer graphs?
    Why?

------------------------------------------------------------------------

# Submission Instructions

Submit a **single zip file** containing:

    src/bfs_pointer.c
    src/bfs_csr.c
    src/graph_csr.c
    report.pdf

Do **not modify**:

    graph_loader.c
    benchmark.c
    main.c

Your code must compile with:

    make
