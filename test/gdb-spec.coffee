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

waitStop = (gdb) ->
    if gdb.exec.state != 'RUNNING'
        return Promise.resolve()
    new Promise (resolve, reject) ->
        x = new CompositeDisposable
        x.add gdb.exec.onExited ->
            x.dispose()
            reject new Error 'Target exited'
        x.add gdb.exec.onStopped ({frame}) ->
            x.dispose()
            resolve frame

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
        gdb.exec.start()
        .then ->
            assert(gdb.exec.state == 'RUNNING')
            waitStop(gdb)
        .then (frame) ->
            assert frame.file.match /.*simple\.c$/
            assert frame.func == 'main'

    beforeEach ->
        gdb.exec.start()
        .then -> waitStop(gdb)

    it 'can resume execution', (done) ->
        gdb.exec.onExited ->
            done()
        gdb.exec.continue()
        return

    it 'can step over function calls', ->
        gdb.exec.next()
        .then -> waitStop(gdb)
        .then (frame) ->
            assert frame.func == 'main'

    it 'can step into function calls', ->
        gdb.exec.step()
        .then -> waitStop(gdb)
        .then (frame) ->
            assert frame.func == 'func1'

    it 'can step out of function calls', ->
        gdb.exec.step()
        .then -> waitStop(gdb)
        .then -> gdb.exec.finish()
        .then -> waitStop(gdb)
        .then (frame) ->
            assert frame.func == 'main'

    it 'notifies observers of state changes', ->
        stateSequence = []
        x = new CompositeDisposable
        x.add gdb.exec.onExited -> stateSequence.push 'exit'
        x.add gdb.exec.onRunning -> stateSequence.push 'run'
        x.add gdb.exec.onStopped -> stateSequence.push 'stop'
        gdb.exec.next()
        .then -> waitStop(gdb)
        .then -> gdb.exec.continue()
        .then -> waitStop(gdb)
        .catch ->
            x.dispose()
            assert stateSequence.length == 4
            assert stateSequence[0] == 'run'
            assert stateSequence[1] == 'stop'
            assert stateSequence[2] == 'run'
            assert stateSequence[3] == 'exit'

    it 'can read the list of threads', ->
        gdb.exec.getThreads()

    it 'can read a stack backtrace', ->
        gdb.exec.step()
        .then -> waitStop(gdb)
        .then -> gdb.exec.step()
        .then -> waitStop(gdb)
        .then -> gdb.exec.getFrames()
        .then (frames) ->
            assert frames.length == 3
            assert frames[0].func == 'func2'
            assert frames[1].func == 'func1'
            assert frames[2].func == 'main'

    it 'can examine local variables', ->
        gdb.exec.step()
        .then -> waitStop(gdb)
        .then -> gdb.exec.step()
        .then -> waitStop(gdb)
        .then -> gdb.exec.getLocals(0)
        .then (locals) ->
            assert locals[0].name == 'b1' and locals[0].value == '2'
            assert locals[1].name == 'b2' and locals[1].value == '1'
        .then -> gdb.exec.getLocals(1)
        .then (locals) ->
            assert locals[0].name == 'a' and locals[0].value == '1'

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
        gdb.exec.continue()
        .then ->
            waitStop(gdb)
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
            gdb.exec.onExited -> done()
            gdb.exec.continue()
        return
