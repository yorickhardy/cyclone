;;;; Cyclone Scheme
;;;; https://github.com/justinethier/cyclone
;;;;
;;;; Copyright (c) 2014-2019, Justin Ethier
;;;; All rights reserved.
;;;;
;;;; This file is part of the cps-optimizations module.
;;;;

(cond-expand 
  (program
    (import (scheme base) 
            (scheme write) 
            (scheme cyclone ast) 
            (scheme cyclone primitives)
            (scheme cyclone transforms)
            (scheme cyclone cps-optimizations)
            (scheme cyclone util) 
            (scheme cyclone pretty-print)
            (srfi 2)
            (srfi 69)
            )
    ))

;; TODO: function to actually scan a def to see if that def can be memoized
(define (memoizable? var body)
  (define cont #f)
  (define (scan exp return)
    ;(trace:error `(DEBUG scan ,(ast:ast->pp-sexp exp)))
    (write `(DEBUG scan ,var ,cont ,(ast:ast->pp-sexp exp))) (newline)
    (cond
     ;; TODO: reject if a lambda is returned
     ((ast:lambda? exp)
      (map
        (lambda (e)
          (scan e return))
        (ast:lambda-body exp))
     )
     ((quote? exp) exp)
     ((const? exp) #t)
     ((ref? exp) exp)
     ((define? exp)
      (return #f))
     ((set!? exp)
      (return #f))
     ((if? exp)
      (scan (if->condition exp) return)
      (scan (if->then exp) return)
      (scan (if->else exp) return))
     ((app? exp)
      (cond
        ;(write `( ,(car exp) ,var ,cont)) (newline)
        ((ast:lambda? (car exp))
         (scan (car exp) return))
        ((or
            (equal? (car exp) var)  ;; Recursive call to self
            (equal? (car exp) cont) ;; Continuation of fnc
         )
         #t) ;; OK to ignore this call 
        ((not (member 
                (car exp)
               '(+ - * / = 
                Cyc-fast-plus
                Cyc-fast-sub
                Cyc-fast-mul
                Cyc-fast-div
                Cyc-fast-eq
                Cyc-fast-gt
                Cyc-fast-lt
                Cyc-fast-gte
                Cyc-fast-lte
                Cyc-fast-char-eq
                Cyc-fast-char-gt
                Cyc-fast-char-lt
                Cyc-fast-char-gte
                Cyc-fast-char-lte
                =
                >
                <
                >=
                <=
                )))
         ;; Call not on approved list
         (return #f)))
      (for-each
        (lambda (e)
          (scan e return))
        (cdr exp)))
     (else exp)
  ))
  (cond
    ((and-let* 
      ((ref? var)
       (ast:lambda? body)
       (eq? (ast:lambda-formals-type body) 'args:fixed)
       (adb:get/default var #f)
       (adbv:self-rec-call? var)
      ) 
      #t)
     (call/cc
      (lambda (return)
        (set! cont (car (ast:lambda-args body)))
        (scan body return)
        (return #t))))
    (else #f))
)

(define (analyze:memoize-pure-fncs sexp)
  ;; exp - S-expression to scan
  (define (scan exp)
    ;(trace:error `(DEBUG scan ,(ast:ast->pp-sexp exp)))
    (cond
     ((ast:lambda? exp)
      exp
     )
     ((quote? exp) exp)
     ((const? exp) exp)
     ((ref? exp) exp)
     ((define? exp) 
      ;; TODO: support non-top-level defines in the future as well

      ;; TODO: is this a candidate function? if so, scan it using (memoizable?)
      (let ((var (define->var exp))
            (body (car (define->exp exp))))
        (cond
          ((memoizable? var body)
            (write `(DEBUG ,var is memoizable))
            (newline)
            ;; TODO: easy to rename function via gensym. however, also
            ;; need to inject this into top-level:
            ;; (define fib #f)
            ;; and wrap top-level portion with
            ;;   (memoize
            ;;     (lambda-22
            ;;       (r$78)
            ;;       (Cyc-seq
            ;;         (set-global! ack r$78)
            ;;         .. existing top-level goes here
            ;;     ))
            ;;     _ack)
            exp)
          (else exp))))
     ;((set!? exp)
     ; ;; TODO: probably need to keep track of var here
     ; (scan (set!->var exp) vars)
     ; (scan (set!->exp exp) vars))
     ((if? exp) exp)
     ((app? exp)
      (map scan exp))
     (else exp)
  ))
  (scan sexp)
)


(cond-expand
  (program
    (define (trace:error exp)
      (write exp)
      (newline))
    (define sexp
'(

 (define fnc
   (lambda
     (k$41 x$5$21 y$6$22)
     (k$41 (Cyc-fast-plus x$5$21 y$6$22))))
 (define mfnc #f)
 (define ack
   (lambda
     (k$46 m$7$23 n$8$24)
     ((lambda
        (r$47)
        (if r$47
          ((lambda () (k$46 (Cyc-fast-plus n$8$24 1))))
          ((lambda
             (r$48)
             (if r$48
               ((lambda
                  ()
                  ((lambda (r$49) (ack k$46 r$49 1))
                   (Cyc-fast-sub m$7$23 1))))
               ((lambda
                  ()
                  ((lambda
                     (r$50)
                     ((lambda
                        (r$52)
                        (ack (lambda (r$51) (ack k$46 r$50 r$51))
                             m$7$23
                             r$52))
                      (Cyc-fast-sub n$8$24 1)))
                   (Cyc-fast-sub m$7$23 1))))))
           (Cyc-fast-eq n$8$24 0))))
      (Cyc-fast-eq m$7$23 0))))
 (define fib
   (lambda
     (k$55 n$16$25)
     ((lambda
        (r$56)
        (if r$56
          (k$55 n$16$25)
          ((lambda
             (r$60)
             (fib (lambda
                    (r$57)
                    ((lambda
                       (r$59)
                       (fib (lambda
                              (r$58)
                              (k$55 (Cyc-fast-plus r$57 r$58)))
                            r$59))
                     (Cyc-fast-sub n$16$25 2)))
                  r$60))
           (Cyc-fast-sub n$16$25 1))))
      (Cyc-fast-lt n$16$25 2))))

))

(let ((ast (ast:sexp->ast sexp)))
  (analyze-cps ast)
  ;(analyze:find-recursive-calls ast)
  (pretty-print
    (ast:ast->pp-sexp
      (analyze:memoize-pure-fncs ast))))

;;    (pretty-print
;;      (ast:ast->pp-sexp
;;        (ast:sexp->ast sexp)))
;;    
;;    (newline)
;;    (newline)
;;
;;    (let ((ht (analyze:build-call-graph (ast:sexp->ast sexp))))
;;      (pretty-print (hash-table->alist ht))
;;      (newline)
;;;; TODO: store table and call these to test various vars:
;;(analyze:find-inlinable-vars (ast:sexp->ast sexp) '()) ;; Identify variables safe to inline
;;(pretty-print (inline-ok-from-call-graph? 'm$30$47 ht))
;;(newline)
;;(pretty-print (inline-ok-from-call-graph? 'zzz ht))
;;(newline)
;;    )
;;
;;    ;(pretty-print
;;    ;  (ast:ast->pp-sexp
;;    ;    (opt:local-var-reduction (ast:sexp->ast sexp)))
;;    ;)
))