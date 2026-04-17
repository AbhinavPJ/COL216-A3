
#include "graph.h"
#include "queue.h"
#include <stdlib.h>
int bfs_pointer(Graph *g, int source, int *dist) {
  int visited_count = 0;
  for (int i = 0; i < g->num_vertices; i++) {
    dist[i] = -1;
  }
  dist[source] = 0;
  visited_count++;
  Queue *queue = create_queue(g->num_vertices);
  enqueue(queue, source);
  while (!is_empty(queue)) {
    int u = dequeue(queue);
    Edge *edge = g->vertices[u].head;
    while (edge) {
      int v = edge->dst;
      if (dist[v] == -1) {
        visited_count++;
        dist[v] = dist[u] + 1;
        enqueue(queue, v);
      }
      edge = edge->next;
    }
  }
  free_queue(queue);
  return visited_count;
}
