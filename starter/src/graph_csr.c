
#include "graph.h"
#include <stdlib.h>
CSRGraph *convert_to_csr(Graph *g) {
  CSRGraph *csr = (CSRGraph *)malloc(sizeof(CSRGraph));
  if (!csr) {
    return NULL;
  }
  csr->num_vertices = g->num_vertices;
  int num_edges = 0;
  int *row_ptr = (int *)malloc((g->num_vertices + 1) * sizeof(int));
  if (!row_ptr) {
    free(csr);
    return NULL;
  }
  row_ptr[0] = 0;
  int current_edge = 0;
  for (int i = 0; i < g->num_vertices; i++) {
    Edge *e = g->vertices[i].head;
    int out_degree = 0;
    while (e) {
      out_degree++;
      num_edges++;
      e = e->next;
    }
    current_edge += out_degree;
    row_ptr[i + 1] = current_edge;
  }
  int *col_idx = (int *)malloc(num_edges * sizeof(int));
  if (!col_idx) {
    free(row_ptr);
    free(csr);
    return NULL;
  }
  int edge_index = 0;
  for (int i = 0; i < g->num_vertices; i++) {
    Edge *e = g->vertices[i].head;
    while (e) {
      col_idx[edge_index++] = e->dst;
      e = e->next;
    }
  }
  csr->row_ptr = row_ptr;
  csr->col_idx = col_idx;
  return csr;
}
void free_csr(CSRGraph *g) {
  if (!g)
    return;
  free(g->row_ptr);
  free(g->col_idx);
  free(g);
}
