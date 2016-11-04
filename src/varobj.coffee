{Emitter, Disposable, CompositeDisposable} = require 'event-kit'
{cstr} = require './utils'
_ = require 'underscore'

# Class representing a target variable
# Should not be created directly, but by calling {VariableManager#add}.
class Variable
    watchpoint: null

    # @nodoc
    constructor: (@gdb, varobj) ->
        @emitter = new Emitter
        _.extend this, varobj

    # Invoke the given callback function when this variable is changed.
    # @return [Disposable] to unsubscribe.
    onChanged: (cb) ->
        @emitter.on 'changed', cb

    # Invoke the given callback function when this variable is deleted.
    # @return [Disposable] to unsubscribe.
    onDeleted: (cb) ->
        @emitter.on 'deleted', cb

    # Assign a new value to this variable
    # @param val [String] new value
    # @return [Promise] resolves to new value if accepted
    assign: (val) ->
        @gdb.send_mi "-var-assign #{@name} #{cstr(val)}"
        .then ({value}) =>
            @gdb.vars.update()
            value

    # @private
    _getExpression: ->
        @gdb.send_mi "-var-info-path-expression #{@name}"
            .then ({path_expr}) ->
                path_expr

    # Set a watchpoint on this variable
    setWatch: ->
        @_getExpression()
        .then (expr) =>
            @gdb.breaks.insertWatch expr, (number) =>
                @gdb.vars.watchpoints[number] = @name
        .then (bkpt) => @_watchSet(bkpt)

    # Clear the watchpoint on this variable
    clearWatch: ->
         @watchpoint.remove()

    # Remove this variable
    remove: ->
        @gdb.send_mi "-var-delete #{@name}"
        .then => @_deleted()

    # Add children
    addChildren: ->
        @gdb.send_mi "-var-list-children --all-values #{@name}"
        .then (result) =>
            Promise.all (@gdb.vars._added(child) for child in result.children.child)
        .then (@children) =>
            @children

    # @private
    _watchSet: (bkpt) ->
        @watchpoint = bkpt
        bkpt.onDeleted =>
            delete @watchpoint
        bkpt.onChanged =>
            @_changed()
        @_changed()

    # @private
    _changed: (varobj) ->
        _.extend this, varobj
        @emitter.emit 'changed', this

    # @private
    _deleted: ->
        @emitter.emit 'deleted'
        @emitter.dispose()
        @watchpoint?.remove()
        for child in @children?
            child._deleted()

class VariableManager
    # @nodoc
    constructor: (@gdb) ->
        @roots = []
        @vars = {}
        @observers = []
        @watchpoints = {}
        @emitter = new Emitter
        @subscriptions = new CompositeDisposable
        @subscriptions.add @gdb.exec.onStateChanged @_execStateChanged.bind(this)
        @subscriptions.add @gdb.breaks.observe @_breakObserver.bind(this)

    # @private
    destroy: ->
        @subscriptions.dispose()
        @emitter.dispose()
        delete @observers
        delete @watchpoints
        delete @roots
        delete @vars

    # Invoke the callback function for each existing and future {Variable}
    # @param [Function] cb Function to call with {Variable} as paramter
    # @return [Disposable] to unsubscribe.
    observe: (cb) ->
        # Recursively notify observer of existing items
        r = (n) =>
            v = @vars[n]
            cb n, v
            r(n) for n in v.children or []
        r(n) for n in @roots
        @observers.push cb
        return new Disposable () ->
            @observers.splice(@observers.indexOf(cb), 1)

    # Create a new {Variable} object
    # @param expr [String] target expression to watch
    # @param frame [Integer] Stack level (optional)
    # @param thread [String] Target thread identifier (optional)
    # @return [Promise] resolves to the new {Variable}
    add: (expr, frame, thread) ->
        thread ?= @gdb.exec.selectedThread
        frame ?= @gdb.exec.selectedFrame
        @gdb.send_mi "-var-create --thread #{thread} --frame #{frame} - * #{cstr(expr)}"
            .then (result) =>
                result.exp = expr
                @_added result

    evalExpression: (expr, frame, thread) ->
        thread ?= @gdb.exec.selectedThread
        frame ?= @gdb.exec.selectedFrame
        @gdb.send_mi "-data-evaluate-expression --thread #{thread} --frame #{frame} #{expr}"
            .then ({value}) ->
                value

    # @private
    _notifyObservers: (v) ->
        cb(v) for cb in @observers
        return v

    # @private
    _execStateChanged: ([state]) ->
        if state == 'DISCONNECTED'
            for name in @roots.slice()
                @_removeVar name
            return
        if state != 'STOPPED' then return
        @update()

    # @private
    update: ->
        @gdb.send_mi "-var-update --all-values *"
            .then ({changelist}) =>
                for v in changelist
                    @vars[v.name]._changed(v)

    # @private
    _added: (v) ->
        if (i = v.name.lastIndexOf '.') >= 0
            v.parent = @vars[v.name.slice(0, i)]
        v.nest = v.name.split('.').length - 1
        v = new Variable(@gdb, v)
        @vars[v.name] = v
        v.onDeleted =>
            delete @vars[v.name]
            if v.name in @roots
                @roots.splice(@roots.indexOf(v.name), 1)
        @_notifyObservers v

    # @private
    _breakObserver: (id, bkpt) ->
        if not bkpt.type.endsWith('watchpoint')
            return

        if @watchpoints[id]?
            return
        # We don't know about this, create a new var obj
        @add(bkpt.what)
        .then (v) =>
            @watchpoints[bkpt.number] = v.name
            v._watchSet(bkpt)

module.exports = VariableManager
