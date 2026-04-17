#ifndef QUEUE_H
#define QUEUE_H
#include <stdbool.h>
#include <stdlib.h>
typedef struct Queue {
  int *data;
  int front;
  int rear;
  int capacity;
} Queue;
Queue *create_queue(int capacity);
void free_queue(Queue *q);
bool is_empty(Queue *q);
int is_full(Queue *q);
void enqueue(Queue *q, int value);
int dequeue(Queue *q);
#endif
