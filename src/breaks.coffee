{Emitter, Disposable, CompositeDisposable} = require 'event-kit'
_ = require 'underscore'

# A class representing a single breakpoint.  This should not be created directly
# but by calling {BreakpointManager::create}.
class Breakpoint
    constructor: (@gdb, bkpt) ->
        @emitter = new Emitter
        _.extend this, bkpt

    # Public: Invoke the given callback function when this breakpoint
    # is modified.
    #
    # Returns a `Disposable` on which `.dispose()` can be called to unsubscribe.
    onChanged: (cb) ->
        @emitter.on 'changed', cb

    # Public: Invoke the given callback function when this breakpoint
    # is deleted.
    #
    # Returns a `Disposable` on which `.dispose()` can be called to unsubscribe.
    onDeleted: (cb) ->
        @emitter.on 'deleted', cb

    # Public: Remove this breakpoint from the target.
    #
    # Returns a `Promise` that resolves on success.
    remove: ->
        @gdb.send_mi "-break-delete #{@number}"
            .then => @_deleted()

    _changed: (bkpt) ->
        _.extend this, bkpt
        @emitter.emit 'changed'

    _deleted: ->
        @emitter.emit 'deleted'
        @emitter.dispose()

# Class to manage the creation of new {Breakpoint}s.
module.exports =
class BreakpointManager
    constructor: (@gdb) ->
        @breaks = {}
        @observers = []
        @subscriptions = new CompositeDisposable
        @subscriptions.add @gdb.onAsyncNotify(@_onAsyncNotify.bind(this))
        @subscriptions.add @gdb.exec.onStateChanged @_onStateChanged.bind(this)

    # Public: Invoke the given callback function with all current and future
    # breakpoints in the target.
    observe: (cb) ->
        for id, bkpt of @breaks
            cb id, bkpt
        @observers.push cb
        return new Disposable () ->
            @observers?.splice(@observers.indexOf(cb), 1)

    # Public: Insert a new breakpoint at the given position.
    #
    # Returns a `Promise` that resolves to the new {Breakpoint}
    insert: (pos, options) ->
        flags = ''
        if options?.temp then flags += ' -t'
        @gdb.send_mi "-break-insert #{flags} #{pos}"
            .then ({bkpt}) =>
                @_add bkpt

    insertWatch: (expr, hook) ->
        @gdb.send_mi "-break-watch #{expr}"
            .then ({wpt}) =>
                if hook? then hook(wpt.number)
                @gdb.send_mi "-break-info #{wpt.number}"
            .then (results) =>
                @_add results.BreakpointTable.body.bkpt[0]

    toggle: (file, line) ->
        for id, bkpt of @breaks
            if bkpt.fullname == file and +bkpt.line == line
                bkpt.remove()
                removed = true
        if not removed
            @insert "#{file}:#{line}"

    destroy: ->
        @subscriptions.dispose()
        for n, bkpt of @breaks
            bkpt._deleted()
            delete @breaks[n]
        delete @observers

    _add: (bkpt) ->
        bkpt = @breaks[bkpt.number] = new Breakpoint(@gdb, bkpt)
        bkpt.onDeleted => delete @breaks[bkpt.number]
        for cb in @observers
            cb bkpt.number, bkpt
        bkpt

    _onAsyncNotify: ([cls, {id, bkpt}]) ->
        switch cls
            when 'breakpoint-created'
                @_add bkpt
            when 'breakpoint-modified'
                @breaks[bkpt.number]._changed(bkpt)
            when 'breakpoint-deleted'
                @breaks[id]._deleted()
                delete @breaks[id]

    _onStateChanged: ([state]) ->
        if state == 'DISCONNECTED'
            for id, bkpt of @breaks
                bkpt._deleted()
            @breaks = {}
