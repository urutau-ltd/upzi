;;; maak.scm --- Build automation for upzi using Maak
;;; -*- mode: scheme; -*-
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2026 Urutau-Ltd <softwarelibre@urutau-ltd.org>
;;;
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the  GNU General Public License as published by
;;; the Free Software Foundation, either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
;;; See the GNU General Public License for more details.
(define-module (maak)
  #:declarative? #t
  #:use-module (maak maak)
  #:use-module (ice-9 ftw))

(define project-name
  'upzi)

(define (test)
  "Run the test suite"
  ($ '("zig" "build" "test" "--summary" "all")
     #:verbose? #t))

(define (build)
  "Build the project executable"
  ($ '("zig" "build" "-Doptimize=ReleaseSafe")
     #:verbose? #t))

(define (build-test)
  "Test if the project compiles"
  ($ '("zig" "build" "run" "--" "help")
     #:verbose? #t))

(define (clean)
  "Cleanup build artifacts"
  ($ '("rm" "-rf" ".zig-cache" "zig-out")
     #:verbose? #t))

(define (default)
  (build-test))
