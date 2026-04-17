
#include "graph.h"
#include <stdlib.h>
int bfs_csr(CSRGraph *g, int source, int *dist) {
  int visited_count = 0;
  int *q = (int *)malloc((size_t)g->num_vertices * sizeof(int));
  int front = 0;
  int rear = 0;
  for (int i = 0; i < g->num_vertices; i++)
    dist[i] = -1;
  dist[source] = 0;
  visited_count++;
  q[rear++] = source;
  while (front < rear) {
    int u = q[front++];
    for (int i = g->row_ptr[u]; i < g->row_ptr[u + 1]; i++) {
      int v = g->col_idx[i];
      if (dist[v] == -1) {
        dist[v] = dist[u] + 1;
        visited_count++;
        q[rear++] = v;
      }
    }
  }
  free(q);
  return visited_count;
}
