
#include "graph.h"
#include <stdlib.h>
int bfs_pointer(Graph *g, int source, int *dist) {
  int visited_count = 0;
  for (int i = 0; i < g->num_vertices; i++) {
    dist[i] = -1;
  }
  dist[source] = 0;
  visited_count++;
  int *queue = (int *)malloc((size_t)g->num_vertices * sizeof(int));
  int front = 0;
  int rear = 0;
  queue[rear++] = source;
  while (front < rear) {
    int u = queue[front++];
    Edge *edge = g->vertices[u].head;
    while (edge) {
      int v = edge->dst;
      if (dist[v] == -1) {
        visited_count++;
        dist[v] = dist[u] + 1;
        queue[rear++] = v;
      }
      edge = edge->next;
    }
  }
  free(queue);
  return visited_count;
}
