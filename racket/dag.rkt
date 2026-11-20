#lang racket
(require json
         racket/list
         racket/set)

(provide load-dag
         save-dag
         add-node
         ancestors
         verified?)

;; DAG maps immutable node IDs to node records.
(define (load-dag path)
  (if (file-exists? path)
      (call-with-input-file path read-json)
      (hash)))

(define (save-dag path graph)
  (call-with-output-file path
    #:exists 'replace
    (lambda (out)
      (write-json graph out))))

(define (ancestors graph id)
  (define (visit current seen)
    (for/fold ([acc seen])
              ([p (in-list
                   (hash-ref
                    (hash-ref graph current)
                    'parents
                    '()))])
      (if (set-member? acc p)
          acc
          (visit p (set-add acc p)))))
  (visit id (set)))

(define (add-node graph node)
  (define id (hash-ref node 'id))
  (define parents (hash-ref node 'parents '()))
  (when (hash-has-key? graph id)
    (error 'add-node "Node already exists: ~a" id))
  (when (member id parents)
    (error 'add-node "Self reference: ~a" id))
  (for ([p (in-list parents)])
    (unless (hash-has-key? graph p)
      (error 'add-node "Missing parent: ~a" p)))
  (define next (hash-set graph id node))
  (ancestors next id)
  next)

(define (verified? node)
  (equal?
   (hash-ref (hash-ref node 'verification) 'status)
   "proved"))
