GDB = require '../src'
sinon = require 'sinon'
assert = require 'assert'
child_process = require 'child_process'
{CompositeDisposable} = require 'event-kit'

testfile = (gdb, srcfile) ->
    new Promise (resolve, reject) ->
        binfile = 'test/bin/' + srcfile.slice(0, srcfile.lastIndexOf('.'))
        srcfile = 'test/src/' + srcfile
        child_process.exec "cc -g -O0 -o #{binfile} #{srcfile}", (err) ->
            if err? then reject(err) else resolve(binfile)
    .then (binfile) ->
        gdb.setFile binfile

waitStop = (gdb, cmd) ->
    new Promise (resolve, reject) ->
        x = new CompositeDisposable
        x.add gdb.exec.onRunning ->
            x.add gdb.exec.onExited ->
                x.dispose()
                reject new Error 'Target exited'
            x.add gdb.exec.onStopped (result) ->
                x.dispose()
                resolve result.frame
        cmd()

describe 'GDB core', ->
    gdb = null
    beforeEach ->
        gdb = new GDB()
        #gdb.onGdbmiRaw (data) -> console.log data

    afterEach -> gdb?.destroy()

    describe 'Connecting and disconnecting', ->
        it 'emits connected when connecting', ->
            spy = sinon.spy()
            gdb.onConnect spy
            gdb.connect().then ->
                assert spy.called

        it 'emits disconnected when disconnecting', (done) ->
            gdb.onDisconnect done
            gdb.connect()
            .then ->
                gdb.disconnect()
            return

        it 'emits disconnected then connected when reconnecting', ->
            disconnect = sinon.spy()
            connect = sinon.spy ->
                assert(disconnect.called)
            gdb.connect()
            .then ->
                gdb.onDisconnect disconnect
                gdb.onConnect connect
                gdb.connect()
            .then ->
                assert(connect.called)

        it "rejects promise if can't spawn child", ->
            gdb.connect("unlikely-to-exist")
            .then ->
                assert(not "Shouldn't get here")
            .catch (err) ->
                assert(err.constructor is Error)

    describe 'When connected', ->
        beforeEach ->
            gdb.connect()

        it 'accepts cli commands and emits console-output event', ->
            spy = sinon.spy()
            gdb.onConsoleOutput spy
            gdb.send_cli 'show version'
            .then ->
                assert spy.called

        it 'ignore comment lines on cli', ->
            gdb.send_cli ' #some comment'

        it 'rejects bad cli command with exception', ->
            gdb.send_cli 'badcommand'
            .then ->
                assert(not "Shouldn't get here")
            .catch (err) ->
                assert(err.constructor is Error)

        it 'accepts cwd', ->
            gdb.setCwd('.')

        it 'rejects invalid cwd', ->
            gdb.setCwd('./unlikely-to-exist')
            .then ->
                assert(not "Shouldn't get here")
            .catch (err) ->
                assert(err.constructor is Error)

        it 'allows setting internal variables', ->
            gdb.set('confirm', 'off')
            .then ->
                gdb.show('confirm')
            .then (foo) ->
                assert(foo == 'off')

        it 'allow setting target binary', ->
            testfile(gdb, 'simple.c')

        it 'rejects non-existant binary', ->
            gdb.setFile('garbage')
            .then ->
                assert(false)
            .catch (err) ->
                assert(err.constructor is Error)

describe 'GDB Execution State', ->
    gdb = null
    beforeEach ->
        gdb = new GDB()
        #gdb.onGdbmiRaw (data) -> console.log data
        gdb.connect()
        .then -> testfile(gdb, 'simple.c')

    it 'can start the target program', ->
        waitStop gdb, -> gdb.exec.start()
        .then (frame) ->
            assert frame.file.match /.*simple\.c$/
            assert frame.func == 'main'

    beforeEach ->
        waitStop gdb, => gdb.exec.start()

    it 'can resume execution', (done) ->
        gdb.exec.onExited ->
            done()
        gdb.exec.continue()
        return

    it 'can step over function calls', ->
        waitStop gdb, -> gdb.exec.next()
        .then (frame) ->
            assert frame.func == 'main'

    it 'can step into function calls', ->
        waitStop gdb, -> gdb.exec.step()
        .then (frame) ->
            assert frame.func == 'func1'

    it 'can step out of function calls', ->
        waitStop gdb, -> gdb.exec.step()
        .then -> waitStop gdb, -> gdb.exec.finish()
        .then (frame) ->
            assert frame.func == 'main'

    it 'notifies observers of state changes', ->
        stateSequence = []
        x = new CompositeDisposable
        x.add gdb.exec.onExited -> stateSequence.push 'exit'
        x.add gdb.exec.onRunning -> stateSequence.push 'run'
        x.add gdb.exec.onStopped -> stateSequence.push 'stop'
        waitStop gdb, -> gdb.exec.next()
        .then -> waitStop(gdb, -> gdb.exec.continue())
        .catch (err) ->
            x.dispose()
            assert stateSequence.length == 4
            assert stateSequence[0] == 'run'
            assert stateSequence[1] == 'stop'
            assert stateSequence[2] == 'run'
            assert stateSequence[3] == 'exit'

    it 'can read the list of threads', ->
        gdb.exec.getThreads()

    it 'can read a stack backtrace', ->
        waitStop gdb, -> gdb.exec.step()
        .then -> waitStop gdb, -> gdb.exec.step()
        .then -> gdb.exec.getFrames()
        .then (frames) ->
            assert frames.length == 3
            assert frames[0].func == 'func2'
            assert frames[1].func == 'func1'
            assert frames[2].func == 'main'

    it 'can examine local variables', ->
        waitStop gdb, -> gdb.exec.step()
        .then -> waitStop gdb, -> gdb.exec.step()
        .then -> gdb.exec.getLocals(0)
        .then (locals) ->
            assert locals[0].name == 'b1' and locals[0].value == '2'
            assert locals[1].name == 'b2' and locals[1].value == '1'
        .then -> gdb.exec.getLocals(1)
        .then (locals) ->
            assert locals[0].name == 'a' and locals[0].value == '1'

    it 'can interrupt a running target', ->
        gdb.send_cli 'set spin = 1'
        .then -> waitStop gdb, ->
            gdb.exec.continue()
            gdb.exec.interrupt()

    it 'can interrupt target run from cli', ->
        gdb.send_cli 'set spin = 1'
        .then -> waitStop gdb, ->
            gdb.send_cli 'cont'
            gdb.exec.interrupt()

describe 'GDB Remote target', ->
    gdb = null
    beforeEach ->
        gdb = new GDB()
        #gdb.onGdbmiRaw (data) -> console.log data
        gdb.connect()
        .then -> testfile(gdb, 'simple.c')
        .then -> gdb.send_cli 'target remote | gdbserver - test/bin/simple'

    it 'can interrupt a running target', ->
        gdb.send_cli 'set spin = 1'
        .then ->waitStop gdb, ->
            gdb.exec.continue()
            gdb.exec.interrupt()

    it 'can interrupt target run from cli', ->
        gdb.send_cli 'set spin = 1'
        .then -> waitStop gdb, ->
            gdb.send_cli 'cont'
            gdb.exec.interrupt()

describe 'GDB Breakpoint Manager', ->
    # Breakpoint tests are sequencial and state is preserved between tests
    # If an early test fails, the following tests will also fail
    gdb = null
    bkpt = null

    before ->
        gdb = new GDB()
        #gdb.onGdbmiRaw (data) -> console.log data

        gdb.connect()
        .then -> testfile(gdb, 'simple.c')

    it 'can set a breakpoint', ->
        bpObserver = sinon.spy()
        gdb.breaks.observe bpObserver
        gdb.breaks.insert 'func2'
        .then (b) ->
            bkpt = b
            assert bpObserver.calledWith('1', bkpt)

    it 'can hit a breakpoint', ->
        bpChanged = sinon.spy()
        bkpt.onChanged bpChanged
        waitStop gdb, -> gdb.exec.continue()
        .then (frame) ->
            assert frame.func == 'func2'
            assert bpChanged.called
            assert bkpt.times == '1'

    it 'can remove a breakpoint', (done) ->
        bpDeleted = sinon.spy()
        bkpt.onDeleted bpDeleted
        bkpt.remove()
        .then ->
            assert bpDeleted.called
            x = gdb.exec.onExited ->
                x.dispose()
                done()
            gdb.exec.continue()
        return

    it 'notifies osbervers on cli created breakpoints', ->
        bpObserver = sinon.spy()
        gdb.breaks.observe bpObserver
        gdb.send_cli 'break main'
        .then ->
            assert bpObserver.called
            bkpt = bpObserver.args[0][1]
            assert bkpt.func == 'main'

    it 'notifies observers of cli deleted breakpoints', (done) ->
        bpDeleted = sinon.spy()
        bkpt.onDeleted bpDeleted
        gdb.send_cli "delete #{bkpt.number}"
        .then ->
            assert bpDeleted.called
            x = gdb.exec.onExited ->
                x.dispose()
                done()
            gdb.exec.continue()
        return

describe 'GDB Variable Manager', ->
    gdb = null
    beforeEach ->
        gdb = new GDB()
        #gdb.onGdbmiRaw (data) -> console.log data
        gdb.connect()
        .then -> testfile(gdb, 'struct.c')
        .then -> waitStop gdb, -> gdb.exec.start()

    it 'can add a variable object', ->
        spy = sinon.spy()
        gdb.vars.observe spy
        gdb.vars.add('astruct')
        .then (v) ->
            assert(spy.args[0][0] == v)
            assert(+v.numchild == 3)
            assert(v.exp == 'astruct')
            assert(v.nest == 0)

    it "can enumerate variable's children", ->
        spy = sinon.spy()
        parent = null
        gdb.vars.observe spy
        gdb.vars.add('astruct')
        .then (v) ->
            parent = v
            parent.addChildren()
        .then (children) ->
            assert parent.children == children
            assert children.length == 3
            for i in [0..2]
                assert spy.args[i+1][0] == children[i]
                assert children[i].parent == parent
            assert children[0].exp == 'inner1'
            assert children[1].exp == 'inner2'
            assert children[2].exp == 'c'

    it "can remove a variable object", ->
        spy = sinon.spy()
        gdb.vars.add('astruct')
        .then (v) ->
            v.onDeleted spy
            v.remove()
        .then ->
            assert spy.called

    it "reports changes in variable objects", (done) ->
        changed = (v) ->
            assert v.exp == 'c'
            assert v.value = '20'
            done()
        gdb.vars.add('astruct')
        .then (v) ->
            v.addChildren()
        .then (children) ->
            children[2].onChanged changed.bind(null, children[2])
        .then ->
            gdb.exec.next()
        return

    it "can assign a value to a variable", ->
        gdb.vars.add('astruct')
        .then (v) ->
            v.addChildren()
        .then (children) ->
            children[2].assign "42"
        .then (val) ->
            assert val == "42"

    it "can set a watchpoint on a variable", ->
        changed = sinon.spy()
        gdb.vars.add('astruct.c')
        .then (v) ->
            v.onChanged changed
            v.setWatch()
        .then ->
            assert changed.called
            wpt = changed.args[0][0].watchpoint
            assert wpt.number?
            assert wpt.times?

    it "can clear a watchpoint on a variable", ->
        changed = sinon.spy()
        v = null
        gdb.vars.add('astruct.c')
        .then (view) ->
            v = view
            v.setWatch()
        .then ->
            assert v.watchpoint?
            v.onChanged changed
            v.clearWatch()
        .then ->
            assert not v.watchpoint?
            assert changed.called

    it "automatically creates variables on new watchpoints", (done) ->
        gdb.vars.observe (v) -> v.onChanged (v) ->
            assert v.watchpoint?
            done()
        gdb.send_cli 'watch astruct.c'
        return

    it "can evaluate an arbitrary expression", ->
        gdb.vars.evalExpression "astruct.c"
        .then (val) ->
            assert val == '0'

    it "removes child when parent is removed", ->
        spy = sinon.spy()
        parent = null
        gdb.vars.add('astruct')
        .then (v) ->
            parent = v
            parent.addChildren()
        .then (children) ->
            children[0].onDeleted spy
            parent.remove()
        .then ->
            assert spy.called
