{bufferedProcess, cstr} = require './utils'
{Emitter} = require 'event-kit'
{Parser} = require './gdbmi.js'
Exec = require './exec'
Breaks = require './breaks'
VarObj = require './varobj'

# Public: A class to control an instance of GDB running as a child process.
# The child is not spawned on construction, but only when calling `.connect`
class GDB
    # Public: A {BreakpointManager} instance.
    breaks: null
    # Public: An {ExecState} instance.
    exec: null
    # A {VariableManager} instance.  API not finalised.
    varobj: null

    constructor: ->
        @next_token = 0
        @cmdq = []
        @config = {cmdline: 'gdb', cwd: '', file: '', init: ''}
        @parser = new Parser
        @emitter = new Emitter
        @exec = new Exec(this)
        @breaks = new Breaks(this)
        @varobj = new VarObj(this)

    onConsoleOutput: (cb) ->
        @emitter.on 'console-output', cb
    onGdbmiRaw: (cb) ->
        @emitter.on 'gdbmi-raw', cb

    onAsyncExec: (cb) ->
        @emitter.on 'async-exec', cb
    onAsyncNotify: (cb) ->
        @emitter.on 'async-notify', cb
    onAsyncStatus: (cb) ->
        @emitter.on 'async-status', cb

    # Public: Spawn the GDB child process, and set up with our config.
    #
    # Retuns a `Promise` that resolves when GDB is running.
    connect: ->
        if @child?
            @exec._disconnected()
            @child.kill()
        {cmdline, cwd, file, init} = @config
        # Spawn the GDB child process and connect up event handlers
        bufferedProcess
                command: cmdline
                args: ['-n', '--interpreter=mi']
                stdout: @_line_output_handler.bind(this)
                exit: @_child_exited.bind(this)
            .then (@child) =>
                @send_mi "-gdb-set confirm off"
            .then =>
                if cwd?
                    @send_mi "-environment-cd #{cstr(cwd)}"
            .then =>
                @send_mi "-file-exec-and-symbols #{cstr(file)}"
            .then =>
                @exec._connected()
                Promise.all(@send_cli cmd for cmd in init.split '\n')
            .catch (err) =>
                @exec._disconnected()
                @child.kill()
                delete @child
                throw err

    # Politely request the GDB child process to exit
    disconnect: ->
        # First interrupt the target if it's running
        if not @child? then return
        if @exec.state == 'RUNNING'
            @exec.interrupt()
        @send_mi '-gdb-exit'

    _line_output_handler: (line) ->
        # Handle line buffered output from GDB child process
        @emitter.emit 'gdbmi-raw', line
        try
            r = @parser.parse line
        catch err
            @emitter.emit 'console-output', ['CONSOLE', line + '\n']
        if not r? then return
        @emitter.emit 'gdbmi-ast', r
        switch r.type
            when 'OUTPUT' then @emitter.emit 'console-output', [r.cls, r.cstring]
            when 'ASYNC' then @_async_record_handler r.cls, r.rcls, r.results
            when 'RESULT' then @_result_record_handler r.cls, r.results

    _async_record_handler: (cls, rcls, results) ->
        signal = 'async-' + cls.toLowerCase()
        @emitter.emit signal, [rcls, results]

    _result_record_handler: (cls, results) ->
        c = @cmdq.shift()
        if cls == 'error'
            c.reject results.msg
            @_flush_queue()
            return
        c.resolve results
        @_drain_queue()

    _child_exited: () ->
        # Clean up state if/when GDB child process exits
        console.log 'Child exited'
        @exec._disconnected()
        @_flush_queue()
        delete @child

    # Send a gdb/mi command.  This is used internally by sub-modules.
    #
    # Returns a `Promise` that resolves to the results part of the result record
    # reply or rejected in the case of an error reply.
    send_mi: (cmd, quiet) ->
        # Send an MI command to GDB
        if not @child?
            return Promise.reject new Error('Not connected')
        if @exec.state == 'RUNNING'
            return Promise.reject new Error("Can't send commands while target is running")
        new Promise (resolve, reject) =>
            cmd = @next_token + cmd
            @next_token += 1
            @cmdq.push {quiet: quiet, cmd: cmd, resolve:resolve, reject: reject}
            if @cmdq.length == 1
                @_drain_queue()

    _drain_queue: ->
        c = @cmdq[0]
        if not c? then return
        @emitter.emit 'gdbmi-raw', c.cmd
        @child.stdin c.cmd

    _flush_queue: ->
        for c in @cmdq
            c.reject new Error('Flushed due to previous errors')
        @cmdq = []

    # Public: Send a gdb/cli command.  This may be used to implement a CLI
    # window in a GUI frontend tool, or to send monitor or other commands for
    # which no equivalent MI commands exist.
    #
    # Returns a `Promise` that resolves on success.
    send_cli: (cmd) ->
        @send_mi "-interpreter-exec console #{cstr(cmd)}"

module.exports = GDB
