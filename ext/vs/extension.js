// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
const vscode    = require('vscode');
const fs        = require('fs');
const path      = require('path');
const { spawn } = require('child_process');

const liPath = 'lithium';

let liDiagnostic = {};
let liChannel    = vscode.window.createOutputChannel('lithium');

function runLithium(action, target) {
	let pr = spawn(liPath, [ '-std=VSCodeStd', action + ":" + target]);
		
	pr.stdout.on('data', (data) => {
		liChannel.appendLine(data);
	});

	pr.stderr.on('data', (data) => {
		liChannel.appendLine(data);
	});

	pr.on('close', (code, sig) => {
		fs.readFile('/Users/brigadir/projects/lithium/.lithium/std-out-entities.json', (err, data) => {
			if (err) {
				throw err;
			}
			
			// let dgs = vscode.languages.
			// vscode.
			// for (let i = 0; i < dgs.length; i++) {
			// 	let dg = dgs[i];

			// }

			if (data.length > 0) {
				let entities = JSON.parse(data.toString());
			
				let diags = {};
				for (let i = 0; i < entities.length; i++) {
					let entity = entities[i];
					if (entity.hasOwnProperty('file')) {
						let file   = entity.file;
						let line   = entity.hasOwnProperty('line')   ? parseInt(entity.line, 10)   : 1;
						let column = entity.hasOwnProperty('column') ? parseInt(entity.column, 10) : 1;
						let status = entity.hasOwnProperty('status') ? entity.status : 'warning';
						let msg    = entity.hasOwnProperty('statusMsg') ? entity.statusMsg : 'Unknown';
						let range  = new vscode.Range(new vscode.Position(line - 1, column),
													  new vscode.Position(line - 1, column + 1)); 

						let vs_status = vscode.DiagnosticSeverity.Information;
						if (status == 'error') {
							vs_status = vscode.DiagnosticSeverity.Error;
						} else if (status == 'warning') {
							vs_status = vscode.DiagnosticSeverity.Warning;
						} else if (status == 'info') {
							vs_status = vscode.DiagnosticSeverity.Information;
						} else if (status == 'hint') {
							vs_status = vscode.DiagnosticSeverity.Hint;
						}

						if (!diags.hasOwnProperty(file)) {
							diags[file] = [];
						}

						let location   = new vscode.Location(vscode.Uri.file(file), range);
						let diagnostic = new vscode.Diagnostic(range, msg, vs_status);
					//	diagnostic.relatedInformation = [ new vscode.DiagnosticRelatedInformation(location, "Test") ];
						diags[file].push(diagnostic);										   
					}
				}	

				for (let file in diags) {
					if (liDiagnostic.hasOwnProperty(file)) {
						liDiagnostic[file].clear();
						liDiagnostic[file].dispose();
					}

					liDiagnostic[file] = vscode.languages.createDiagnosticCollection("lithium");
					liDiagnostic[file].clear();
					liDiagnostic[file].set(vscode.Uri.parse("file://" + file + "?test"), diags[file]);
				}
			}
		});			


		liChannel.show(true);
	});
}

function activate(context) {
	let disposable = vscode.commands.registerCommand('extension.lithium.compile', function () {
		runLithium("compile", vscode.window.activeTextEditor.document.fileName);
	});
	context.subscriptions.push(disposable);

	disposable = vscode.commands.registerCommand('extension.lithium.run', function () {
		runLithium("run", vscode.window.activeTextEditor.document.fileName);
	});
	context.subscriptions.push(disposable);

	disposable = vscode.commands.registerCommand('extension.lithium.compileAll', function () {
		liChannel.appendLine("vscode.workspace.rootPath = " +vscode.workspace.rootPath);
		runLithium("compile", vscode.workspace.rootPath);
	});
	context.subscriptions.push(disposable);

	disposable = vscode.commands.registerCommand('extension.lithium.checkstyle', function () {
		runLithium("checkstyle", vscode.window.activeTextEditor.document.fileName);
	});
	context.subscriptions.push(disposable);
}
exports.activate = activate;

// this method is called when your extension is deactivated
function deactivate() {}

module.exports = {
	activate,
	deactivate
}
