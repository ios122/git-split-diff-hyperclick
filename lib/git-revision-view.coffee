_ = require 'underscore-plus'
path = require 'path'
fs = require 'fs'

{CompositeDisposable, BufferedProcess} = require "atom"
{$} = require "atom-space-pen-views"

SplitDiff = null
SyncScroll = null

module.exports =
class GitRevisionView

  @fileContentA = ""
  @fileContentB = ""
  @showRevision: (editor, revA, filePathA, revB, filePathB) ->
    if not SplitDiff
      try
        SplitDiff = require atom.packages.resolvePackagePath('split-diff')
        SyncScroll = require atom.packages.resolvePackagePath('split-diff') + '/lib/sync-scroll'
        atom.themes.requireStylesheet(atom.packages.resolvePackagePath('split-diff') + '/styles/split-diff')
      catch error
        return atom.notifications.addInfo("Git Plus: Could not load 'split-diff' package to open diff view. Please install it `apm install split-diff`.")

    SplitDiff.disable(false)
    @fileContentA = ""
    @fileContentB = ""
    promise = @_getRepo(filePathA)
    @_loadfileContentA(editor, revA, filePathA, revB, filePathB)

  @_loadfileContentA: (editorA, revA, filePathA, revB, filePathB) ->
    @fileContentA = ""
    stdout = (output) ->
      console.log("OUTPUT", output)
      @fileContentA += output
    stderr = (error) ->
      console.log("git-split-diff-hyperclick:ERROR:", error)
    exit = (code) =>
      console.log("CODE", code, @fileContentA)
      if code is 0
        outputFilePath = @_getFilePath(revA, filePathA)
        tempContent = "Loading..." + editor.buffer?.lineEndingForRow(0)
        fs.writeFile outputFilePath, tempContent, (error) ->
          if not error
            promise = atom.workspace.open fullPath,
              split: "left"
              activatePane: false
              activateItem: true
              searchAllPanes: false
            promise.then (editor) ->
              @_loadfileContentB(editorA, revA, filePathA, revB, filePathB)
      else
        atom.notifications.addError "Could not retrieve revision for #{path.basename(filePathA)} (#{code})"

    showArgs = ["show", "#{revA} ./#{filePathA}"]
    console.log('LOAD A', showArgs, filePathA)
    process = new BufferedProcess({
      command: "git",
      args: showArgs,
      options: { cwd:atom.project.getPaths()[0] },
      stdout,
      stderr,
      exit
    })

  @_loadfileContentB: (editorA, revA, filePathA, revB, filePathB) ->

    stdout = (output) ->
      @fileContentB += output
    stderr = (error) ->
      console.log("git-split-diff-hyperclick:ERROR:", error)
    exit = (code) =>
      if code is 0
        @_showRevision(editorA, revA, filePathA, revB, filePathB, @fileContentA, @fileContentB)
      else
        atom.notifications.addError "Could not retrieve revision for #{path.basename(filePathB)} (#{code})"

    showArgs = ["show", "#{revB}:./#{filePathB}"]
    console.log('LOAD B', showArgs, filePathB)
    process = new BufferedProcess({
      command: "git",
      args: showArgs,
      options: { cwd:atom.project.getPaths()[0] },
      stdout,
      stderr,
      exit
    })

  @_getInitialLineNumber: (editor) ->
    editorEle = atom.views.getView editor
    lineNumber = 0
    if editor? && editor != ''
      lineNumber = editorEle.getLastVisibleScreenRow()
      return lineNumber - 5

  @_getFilePath: (rev, filePath) ->
    outputDir = "#{atom.getConfigDirPath()}/git-plus"
    fs.mkdir outputDir if not fs.existsSync outputDir
    return "#{outputDir}/#{rev}#{path.basename(filePath)}.diff"

  @_showRevision: (editorA, revA, filePathA, revB, filePathB) ->
    outputFilePath = @_getFilePath(revB, filePathB)
    tempContent = "Loading..." + editor.buffer?.lineEndingForRow(0)
    fs.writeFile outputFilePath, tempContent, (error) =>
      if not error
        promise = atom.workspace.open file,
          split: "left"
          activatePane: false
          activateItem: true
          searchAllPanes: false
        promise.then (editor) =>
          promise = atom.workspace.open outputFilePath,
            split: "right"
            activatePane: false
            activateItem: true
            searchAllPanes: false
          promise.then (editorB) =>
            @_updateNewTextEditor(editorA, editorB, revA, filePathA, revB, filePathB, fileContents)


  @_updateNewTextEditor: (editorA, editorB, gitRevision, fileContents) ->
    _.delay =>
      lineEnding = editor.buffer?.lineEndingForRow(0) || "\n"
      fileContents = fileContents.replace(/(\r\n|\n)/g, lineEnding)
      editorB.buffer.setPreferredLineEnding(lineEnding)
      editorB.setText(fileContents)
      editorB.buffer.cachedDiskContents = fileContents
      @_splitDiff(editor, editorB)
    , 300

  @_splitDiff: (editor, newTextEditor) ->
    editors =
      editor1: newTextEditor    # the older revision
      editor2: editor           # current rev
    SplitDiff._setConfig 'diffWords', true
    SplitDiff._setConfig 'ignoreWhitespace', true
    SplitDiff._setConfig 'syncHorizontalScroll', true
    SplitDiff.diffPanes()
    SplitDiff.updateDiff(editors)
    syncScroll = new SyncScroll(editors.editor1, editors.editor2, true)
    syncScroll.syncPositions()
