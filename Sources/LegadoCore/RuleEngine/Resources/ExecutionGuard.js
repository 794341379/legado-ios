// Instrument parsed syntax, so comments, strings and finite loops remain valid.
// Acorn offsets and String.slice both use UTF-16 indices.
function instrumentLegadoScript(source, checkName) {
  var tree = acorn.parse(source, { ecmaVersion: 'latest', sourceType: 'script' });
  var edits = [], check = checkName + '();';
  function insert(at, text) { edits.push({ at: at, text: text, order: edits.length }); }
  function blockCheck(block) {
    var at = block.start + 1;
    for (var i = 0; i < block.body.length && block.body[i].directive; i++) at = block.body[i].end;
    insert(at, ';' + check);
  }
  var pending = [tree];
  while (pending.length) {
    var node = pending.pop();
    switch (node.type) {
      case 'WhileStatement': case 'DoWhileStatement': case 'ForStatement':
      case 'ForInStatement': case 'ForOfStatement':
        if (node.body.type === 'BlockStatement') blockCheck(node.body);
        else {
          insert(node.body.start, '{' + check);
          insert(node.body.end, '}');
        }
        break;
      case 'FunctionDeclaration': case 'FunctionExpression': case 'ArrowFunctionExpression':
        if (node.body.type === 'BlockStatement') blockCheck(node.body);
        else {
          insert(node.body.start, '(' + checkName + '(),');
          insert(node.body.end, ')');
        }
        break;
      case 'WithStatement':
        // Only the branded JavaImporter compatibility object may introduce a
        // dynamic scope; arbitrary objects/Proxies could shadow the checks.
        insert(node.object.start, checkName + '.with(');
        insert(node.object.end, ')');
        break;
    }
    for (var key in node) {
      var value = node[key];
      if (value && typeof value.type === 'string') pending.push(value);
      else if (Array.isArray(value)) {
        for (var j = value.length - 1; j >= 0; j--) {
          if (value[j] && typeof value[j].type === 'string') pending.push(value[j]);
        }
      }
    }
  }
  edits.sort(function (a, b) { return b.at - a.at || b.order - a.order; });
  for (var k = 0; k < edits.length; k++) {
    source = source.slice(0, edits[k].at) + edits[k].text + source.slice(edits[k].at);
  }
  return source;
}
