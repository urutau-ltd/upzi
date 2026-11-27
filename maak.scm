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
  ;; `run' below is a task, so the executor it shadows is imported with a
  ;; prefix for the tasks that still need to execute an argv.
  #:use-module ((maak dsl) #:prefix dsl:)
  #:use-module (maak zig))

(quiet? #t)

(define project-name
  'upzi)

(define remotes '("origin" "ro-mirror1" "ro-mirror2"))

(define (test)
  "Run the test suite"
  (zig-build "test" "--summary" "all"))

(define (build)
  "Build the project executable"
  (dsl:run (zig-build-argv '()
                           #:optimize "ReleaseSafe"
                           #:verbose? #t)))

(define (run . arguments)
  "Run the application, passing @var{arguments} to it"
  (apply zig-build-run "--" arguments))

(define (build-test)
  "Test if the project compiles"
  (zig-build-run "--" "--help"))

(define (fmt . paths)
  "Format src and build.zig, or the @var{paths} given"
  (apply zig-fmt (if (null? paths) '("src" "build.zig") paths)))

(define (fmt-check)
  "Check that src and build.zig are formatted"
  (zig-fmt "--check" "src" "build.zig"))

(define (clean)
  "Cleanup build artifacts"
  (delete-file-recursively ".zig-cache")
  (zig-build-clean))

(define (push)
  "Push a commit series to all remotes"
  (for-each (lambda (remote)
              (dsl:run (list "git" "push" remote)))
            remotes))

(define (push-tags)
  "Push all tags to all remotes"
  (for-each (lambda (remote)
              (dsl:run (list "git" "push" remote "--tags")))
            remotes))

(define (default)
  (build-test))
