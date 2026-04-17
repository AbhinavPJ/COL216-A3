#include "queue.h"
#include <stdbool.h>
#include <stdlib.h>
Queue *create_queue(int capacity) {
  Queue *queue = (Queue *)malloc(sizeof(Queue));
  queue->data = (int *)malloc(capacity * sizeof(int));
  queue->front = 0;
  queue->rear = -1;
  queue->capacity = capacity;
  return queue;
}
void enqueue(Queue *queue, int item) {
  if (queue->rear == queue->capacity - 1) {
    return;
  }
  queue->data[++queue->rear] = item;
}
int dequeue(Queue *queue) {
  if (queue->front > queue->rear) {
    return -1;
  }
  return queue->data[queue->front++];
}
bool is_empty(Queue *queue) { return queue->front > queue->rear; }
void free_queue(Queue *queue) {
  free(queue->data);
  free(queue);
}
