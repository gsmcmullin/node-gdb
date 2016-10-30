{Emitter, CompositeDisposable} = require 'event-kit'

module.exports =
# Class for managing target execution state.
class ExecState
    constructor: (@gdb) ->
        @state = 'DISCONNECTED'
        @threadGroups = {}
        @emitter = new Emitter
        @subscriptions = new CompositeDisposable
        @subscriptions.add @gdb.onAsyncExec(@_onExec.bind(this))
        @subscriptions.add @gdb.onAsyncNotify(@_onNotify.bind(this))
        @subscriptions.add @gdb.onConnect => @_setState 'EXITED'
        @subscriptions.add @gdb.onDisconnect => @_setState 'DISCONNECTED'

    destroy: ->
        @subscriptions.dispose()
        @emitter.dispose()

    onFrameChanged: (cb) -> @emitter.on 'frame-changed', cb
    onStopped: (cb) -> @emitter.on 'stopped', cb
    onRunning: (cb) -> @emitter.on 'running', cb
    onExited: (cb) -> @emitter.on 'exited', cb

    onStateChanged: (cb) ->
        @emitter.on 'state-changed', cb

    start: ->
        @gdb.breaks.insert 'main', temp: true
        .then =>
            @gdb.send_mi '-exec-run'

    # Public: Resume execution.
    continue: ->
        if @state == 'EXITED'
            @gdb.send_mi '-exec-run'
        else
            @gdb.send_mi '-exec-continue'

    # Public: Single step, stepping over function calls.
    next: -> @gdb.send_mi '-exec-next'

    # Public: Single step, stepping into function calls.
    step: -> @gdb.send_mi '-exec-step'

    # Public: Resume execution until frame returns.
    finish: -> @gdb.send_mi '-exec-finish'

    # Public: Attempt to interrupt the running target.
    interrupt: ->
        # Interrupt the target if running
        if @state != 'RUNNING'
            return Promise.reject new Error('Target is not running')
        # There is no hope here for Windows.  See issue #4
        if @gdb.config.isRemote
            @gdb.child.process.kill 'SIGINT'
        else
            for id, group of @threadGroups
                process.kill group.pid, 'SIGINT'
        Promise.resolve()

    getThreads: ->
        @gdb.send_mi "-thread-info"

    getFrames: (thread) ->
        @gdb.send_mi "-stack-list-frames --thread #{thread}"
            .then (result) ->
                return result.stack.frame

    selectFrame: (thread, level) ->
        @gdb.send_mi "-thread-select #{thread}"
        @gdb.send_mi "-stack-select-frame #{level}"
        @gdb.send_mi "-stack-info-frame"
            .then ({frame}) =>
                @_setState @state, frame

    getLocals: (thread, level) ->
        @gdb.send_mi "-stack-list-variables --thread #{thread} --frame #{level} --skip-unavailable --all-values"
            .then ({variables}) =>
                variables

    _setState: (state, frame, reason) ->
        if state != @state
            @emitter.emit state.toLowerCase(), {frame, reason}
        @state = state
        @emitter.emit 'state-changed', [state, frame]

    _onExec: ([cls, {reason, frame}]) ->
        switch cls
            when 'running'
                @_setState 'RUNNING'
            when 'stopped'
                if reason? and reason.startsWith 'exited'
                    @_setState 'EXITED'
                    return
                @_setState 'STOPPED', frame

    _onNotify: ([cls, results]) ->
        switch cls
            when 'thread-group-started'
                @threadGroups[results.id] = pid: +results.pid, threads: []
            when 'thread-created'
                @threadGroups[results['group-id']].threads.push results.id
            when 'thread-exited'
                threads = @threadGroups[results['group-id']].threads
                index = threads.indexOf results.id
                threads.splice index, 1
            when 'thread-group-exited'
                delete @threadGroups[results.id]
                if Object.keys(@threadGroups).length == 0 and @state != 'DISCONNECTED'
                    @_setState 'EXITED'
