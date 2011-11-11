require 'json' 
require 'rz/context'
require 'rz/hooking'

module RZ
  module Service
    include Context

    def run
      # initializing sockets
      frontend
      request_socket_a
      request_socket_b

      self.active_req_socket = request_socket_a
      self.blocking_socket   = frontend

      run_hook :before_loop

      loop do
        run_hook :loop_start
        ready = ZMQ.select([response_socket,frontent,active_req_socket],nil,nil,1)
        if ready
          ready.each { |socket| process_ready socket }
        else
          noop
        end
        run_hook :loop_end
      end
    rescue Interrupt
      run_hook :interrupted
      raise
    ensure
      zmq_cleanup
    end

  private

    attr_reader :identity,:frontend_address,:response_address,:request_address_a,:request_address_b

    attr_reader :active_req_socket, :blocking_socket
    private     :active_req_socket, :blocking_socket

    def initialize_service(options)
      @frontend_address      = options.fetch(:frontend_address)    { raise ArgumentError,'missing :frontend_address'  }
      @request_address_a     = options.fetch(:request_address_a)   { raise ArgumentError,'missing :request_address_a' }
      @request_address_b     = options.fetch(:request_address_b)   { raise ArgumentError,'missing :request_address_b' }
      @response_address      = options.fetch(:response_address)    { raise ArgumentError,'missing :response_address'  }
      @identity              = options.fetch(:identity,nil)
    end

    def active_req_socket=(socket)
      if active_req_socket == blocking_socket
        self.blocking_socket = socket
      end
      @active_req_socket=socket
      debug { "switched active req socket to: #{zmq_identity(socket)}" }
    end

    def blocking_socket=(socket)
      return if @blocking_socket == socket
      @blocking_socket = socket
      debug { "switched blocking socket to: #{zmq_identity(socket)}" }
    end

    def switch_active_req_socket
      self.active_req_socket = case active_req_socket
      when request_socket_a then request_socket_b
      when request_socket_b then request_socket_a
      else
        raise
      end
    end

    def process_ready(ready)
      ready.each do |socket|
        case socket
        when response_socket
          p :response
          # Pusing response to client
          addr,body = zmq_split zmq_recv(response_socket)
          zmq_send frontend,body
          run_hook :response
        when frontend
          p :frontend
          # Find worker for job
          message = zmq_recv(active_req_socket,ZMQ::NOBLOCK)
          if message
            job_addr,job_body = zmq_split zmq_recv(frontend)
            worker_addr,worker_body = zmq_split message
            zmq_send active_req_socket,worker_addr + job_addr + DELIM + job_body
            run_hook :request
          else
            self.blocking_socket = active_req_socket
          end
        when active_req_socket
          p :active_req_socket
          # Find job for worker
          message = zmq_recv frontend,ZMQ::NOBLOCK
          if message
            worker_addr,worker_body = zmq_split zmq_recv(active_req_socket)
            job_addr,job_body = zmq_split message
            zmq_send active_req_socket,worker_addr + job_addr + DELIM + job_body
            run_hook :request
          else
            self.blocking_socket = frontend
          end
        else
          raise
        end
      end
      self
    end

    def noop
      loop do
        message = zmq_recv active_req_socket,ZMQ::NOBLOCK
        break unless message
        addr,body = zmq_split message
        zmq_send(active_req_socket,addr + DELIM + NOOP)
      end
      switch_active_req_socket
      run_hook :noop
      self
    end

    def request_socket_a
      zmq_named_socket :request_socket_a,ZMQ::ROUTER do |socket|
        socket.setsockopt ZMQ::IDENTITY,"#{identity}.req.backend.a" if identity
        socket.bind request_address_a
      end
    end

    def request_socket_b
      zmq_named_socket :request_socket_b,ZMQ::ROUTER do |socket|
        socket.setsockopt ZMQ::IDENTITY,"#{identity}.req.backend.b" if identity
        socket.bind request_address_b
      end
    end

    def response_socket
      zmq_named_socket :response_socket,ZMQ::ROUTER do |socket|
        socket.setsockopt ZMQ::IDENTITY,"#{identity}.res.backend" if identity
        socket.bind response_address
      end
    end

    def frontend
      zmq_named_socket :frontend,ZMQ::ROUTER do |socket|
        socket.setsockopt(ZMQ::IDENTITY,"#{identity}.frontend") if identity
        socket.bind frontend_address
      end
    end

    def self.included(base)
      base.send :include,Hooking
    end
  end
end
