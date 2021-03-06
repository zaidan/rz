# Ruby ZeroMQ based job server with truly pulling workers.

This project is primarily a playground to build a ruby job server that solves 
some of my messaging problems using ZMQ primitives. 

Currently the subject is task distribution in a classic multi worker central 
job distribution setup.

[ZeroMQ](http://zeromq.org) is a messaging framework, not a out-of-the-box 
messaging solution. 

So please keep in mind my "Problems" below are not problems of ZMQ itself. 

Maybe this all can be solved just by using rabbbitMQ and friends. But it is 
much more fun to wrap my head around these problems for myself.

### Problem 1: Peers cannot know how busy a worker is.

  This is a generic problem. Peers can only infer worker workload using some 
  more or less accurate heuristics.
  For example haproxy can use connection count. Nginx does round robin out of 
  the box. My problem is the workloads for each job are varying heavy. Some 
  computations only take ~20 ms while others could easily block a worker for 
  several  seconds.
  The central distribution point cannot know the heaviness of a job in advance.
  From my point of view only the worker can decide if he needs more work.

  Background:
    A zmq PULL socket connecting a PUSH socket does not really pull from the 
    server.  It pulls from the local mailbox.
    You basically do not have any control how many messages are in your 
    mailbox, so you do not know if a big job in execution will add latency to 
    many small ones.

### Problem 2: Lost tasks in worker mailboxes on crash

  Task distribution can easily be done using zmqs unique ability to connect more
  than one downstream per socket. Each downstream socket/worker has its own 
  mailbox. 

  Unprocessed messages are lost when this worker crashes. When this mailbox is 
  big or there are many small messages this can hurt latency for the hole 
  system. (Imagine retries are implemented on client side).

  Background:
    ZMQ pushes messages from mailbox to mailbox zmq_recv and zmq_send add or 
    remove messages from this mailbox. A background thread does the transport 
    between mailboxes. You cannot know by design in which mailbox your message 
    currently is.

### Problem 3: Adding workers while processing many jobs

  Imagine a PUSH - PULL zmq setup. 1 PUSH sockets sends 1000 small messages to 
  2 PULL sockets. 
  Each message takes 1 second to process. After 10 seconds you are connecting a 
  3rd worker. But all 1000 messages are already send to one of the workers 
  mailboxes. Bad. Your new worker is waiting for jobs while the other two have 
  to much.

### Idea: Let the workers pull work from the server. 

  When workers are pulling the servers for work there is no worker side queue 
  of unprocessed, lost-in-case-of-crash or 
  present-in-mailbox-while-other-workers-do-not-have-anything-to-do.
  This adds an extra round trip for signalling, and defeats ZMQ message 
  batching, but it might give a better overall latency.

## Implementation:

  To be documented. The current stage works but is far from well designed 
  tested etc...

I really appreciate any input!

## Installation

With git and local working copy:

```bash
$ git clone git://github.com/mbj/rz.git
$ cd rz
$ gem install bundler
$ bundle install
examples/service a &
examples/worker a &
examples/client &
```

NOTE: This gem is currently only tested with 1.9 is likely to work with ruby-1.8
using backports.

## Usage

See examples directory for code.

## Note on Patches/Pull Requests

* If you want your code merged into the mainline, please discuss the proposed 
  changes with me before doing any work on it. This library is still in early 
  development, and it may not always be clear the direction it is going. Some 
  features may not be appropriate yet, may need to be deferred until later when 
  the foundation for them is laid, or may be more applicable in a plugin.
* Fork the project.
* Make your feature addition or bug fix.
* Add specs for it. This is important so I don't break it in a future version 
  unintentionally. Tests must cover all branches within the code, and code must 
  be fully covered. (I'm missing this requirement atm).
* Commit, do not mess with Rakefile, version, or history.  
  (if you want to have your own version, that is fine but bump version in a 
  commit by itself I can ignore when I pull)
* Run "rake ci". This must pass and not show any regressions in the
  metrics for the code to be merged.
* Send me a pull request. Bonus points for topic branches.

## Copyright

Copyright &copy; 2011 Markus Schirp. See LICENSE for details.
