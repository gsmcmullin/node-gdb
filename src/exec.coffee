{Emitter, CompositeDisposable} = require 'event-kit'

# Class for managing target execution state.
class ExecState
    # @nodoc
    constructor: (@gdb) ->
        @state = 'DISCONNECTED'
        @threadGroups = {}
        @emitter = new Emitter
        @subscriptions = new CompositeDisposable
        @subscriptions.add @gdb.onAsyncExec(@_onExec.bind(this))
        @subscriptions.add @gdb.onAsyncNotify(@_onNotify.bind(this))
        @subscriptions.add @gdb.onConnect => @_setState 'EXITED'
        @subscriptions.add @gdb.onDisconnect => @_setState 'DISCONNECTED'

    # @private
    destroy: ->
        @subscriptions.dispose()
        @emitter.dispose()

    onFrameChanged: (cb) -> @emitter.on 'frame-changed', cb
    onStopped: (cb) -> @emitter.on 'stopped', cb
    onRunning: (cb) -> @emitter.on 'running', cb
    onExited: (cb) -> @emitter.on 'exited', cb

    # @private
    onStateChanged: (cb) ->
        @emitter.on 'state-changed', cb

    start: ->
        @gdb.breaks.insert 'main', temp: true
        .then =>
            @gdb.send_mi '-exec-run'

    # Resume execution.
    continue: ->
        if @state == 'EXITED'
            @gdb.send_mi '-exec-run'
        else
            @gdb.send_mi '-exec-continue'

    # Single step, stepping over function calls.
    next: -> @gdb.send_mi '-exec-next'

    # Single step, stepping into function calls.
    step: -> @gdb.send_mi '-exec-step'

    # Resume execution until frame returns.
    finish: -> @gdb.send_mi '-exec-finish'

    # Attempt to interrupt the running target.
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
        thread ?= @selectedThread
        @gdb.send_mi "-stack-list-frames --thread #{thread}"
            .then (result) ->
                return result.stack.frame

    selectFrame: (level, thread) ->
        @gdb.send_mi "-stack-info-frame --thread #{thread} --frame #{level}"
            .then ({frame}) =>
                @_frameChanged frame

    getLocals: (level, thread) ->
        thread ?= @selectedThread
        level ?= @selectedFrame
        @gdb.send_mi "-stack-list-variables --thread #{thread} --frame #{level} --skip-unavailable --all-values"
            .then ({variables}) =>
                variables

    # @private
    _setState: (state, result) ->
        if state != @state
            @emitter.emit state.toLowerCase(), result
        @state = state
        @emitter.emit 'state-changed', [state, result?.frame]

    # @private
    _onExec: ([cls, result]) ->
        switch cls
            when 'running'
                @emitter.emit 'frame-changed', null
                @_setState 'RUNNING'
            when 'stopped'
                if result.reason? and result.reason.startsWith 'exited'
                    @_setState 'EXITED'
                    return
                @_frameChanged result.frame
                @_setState 'STOPPED', result

    # @private
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

    # @private
    _frameChanged: (frame) ->
        @selectedThread = frame['thread-id']
        @selectedFrame = frame.level or 0
        @emitter.emit 'frame-changed', frame

module.exports = ExecState
