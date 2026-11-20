#lang racket
(require "dag.rkt"
         racket/set)

(define failures 0)
(define (check name got expected)
  (if (equal? got expected)
      (printf "PASS ~a\n" name)
      (begin
        (set! failures (+ failures 1))
        (printf "FAIL ~a: got ~a expected ~a\n" name got expected))))

(define (check-error name thunk)
  (with-handlers ([exn:fail? (lambda (e)
                               (printf "PASS ~a (raised: ~a)\n" name (exn-message e)))])
    (thunk)
    (set! failures (+ failures 1))
    (printf "FAIL ~a: no error raised\n" name)))

;; Build the example node from the architecture: agc.gf256.mul.v2
(define cryptol-node
  (hash 'id "cryptol.gf256.mul.v1"
        'parents '()
        'kind "cryptol-spec"
        'verification (hash 'status "proved" 'tool "SAW")))

(define agc-v1-node
  (hash 'id "agc.gf256.mul.v1"
        'parents '()
        'kind "agc"
        'verification (hash 'status "pending" 'tool "SAW")))

(define agc-v2-node
  (hash 'id "agc.gf256.mul.v2"
        'parents '("cryptol.gf256.mul.v1" "agc.gf256.mul.v1")
        'kind "agc"
        'transformation "correct-loop-bound"
        'verification (hash 'status "pending"
                            'tool "SAW"
                            'obligations '("gf256_equivalence"
                                           "loop_termination"
                                           "instruction_semantics"))))

(define g0 (hash))
(define g1 (add-node g0 cryptol-node))
(define g2 (add-node g1 agc-v1-node))
(define g3 (add-node g2 agc-v2-node))

(check "graph has 3 nodes" (hash-count g3) 3)
(check "ancestors of v2" (ancestors g3 "agc.gf256.mul.v2")
       (set "cryptol.gf256.mul.v1" "agc.gf256.mul.v1"))
(check "ancestors of v1 is empty" (ancestors g3 "agc.gf256.mul.v1") (set))
(check "verified? proved node" (verified? cryptol-node) #t)
(check "verified? pending node" (verified? agc-v2-node) #f)

(check-error "duplicate node rejected"
             (lambda () (add-node g3 agc-v2-node)))
(check-error "missing parent rejected"
             (lambda () (add-node g3 (hash 'id "x.v1" 'parents '("no.such.node")))))
(check-error "self reference rejected"
             (lambda () (add-node g3 (hash 'id "self.v1" 'parents '("self.v1")))))

;; save / load round-trip
(define tmp "/tmp/dag_test.json")
(save-dag tmp g3)
(define g4 (load-dag tmp))
(check "load-dag returns 3 nodes" (hash-count g4) 3)
(check "round-trip ancestors of v2" (ancestors g4 "agc.gf256.mul.v2")
       (set "cryptol.gf256.mul.v1" "agc.gf256.mul.v1"))
(check "load-dag missing file gives empty" (hash-count (load-dag "/tmp/no-such-dag.json")) 0)

;; transitive ancestors: add a third-generation node
(define g5 (add-node g4 (hash 'id "vhdl.gf256.mul.v1"
                               'parents '("agc.gf256.mul.v2")
                               'kind "vhdl"
                               'verification (hash 'status "pending" 'tool "SAW"))))
(check "transitive ancestors" (ancestors g5 "vhdl.gf256.mul.v1")
       (set "agc.gf256.mul.v2" "cryptol.gf256.mul.v1" "agc.gf256.mul.v1"))

(printf "~a failures\n" failures)
(exit (if (zero? failures) 0 1))
