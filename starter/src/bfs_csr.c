
#include "graph.h"
#include "queue.h"
#include <stdlib.h>
int bfs_csr(CSRGraph *g, int source, int *dist) {
  int visited_count = 0;
  Queue *q = create_queue(g->num_vertices);
  for (int i = 0; i < g->num_vertices; i++) {
    dist[i] = -1;
  }
  dist[source] = 0;
  visited_count++;
  enqueue(q, source);
  while (!is_empty(q)) {
    int u = dequeue(q);
    for (int i = g->row_ptr[u]; i < g->row_ptr[u + 1]; i++) {
      int v = g->col_idx[i];
      if (dist[v] == -1) {
        dist[v] = dist[u] + 1;
        visited_count++;
        enqueue(q, v);
      }
    }
  }
  free_queue(q);
  return visited_count;
}
