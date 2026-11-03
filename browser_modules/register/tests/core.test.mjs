import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {normalize,documentFor,csvFor,parseCSV,parseFile,fields,safeCell} from '../core.mjs';
const starter=JSON.parse(await readFile(new URL('../../../biostat_pipeline/_register.json',import.meta.url),'utf8'));
const state=normalize(starter);
test('all canonical 132 records and every original field survive JSON and CSV',()=>{
 assert.equal(state.rows.length,132);assert.equal(state.study,'');
 starter.forEach((row,i)=>Object.entries(row).forEach(([key,value])=>assert.equal(state.rows[i][key],value)));
 assert.ok(state.rows.every(r=>r.status==='Not started'));
 assert.deepEqual(normalize(documentFor(state)),state);assert.deepEqual(parseCSV(csvFor(state)),state);
 assert.equal(Object.keys(state.rows[0]).length,fields.length);
});
test('multiline, commas, quotes, Unicode and empty cells survive CSV',()=>{
 const expected=normalize([{id:'X',deliverable:'Δ, "test"\nsecond line',notes:'a\rb\nc\r\nd',owner:''}]);
 assert.deepEqual(parseCSV(csvFor(expected)),expected);
});
test('formula-like cells are neutralized, JSON remains lossless',()=>{
 for(const text of ['=1+1','+SUM(1,2)','-1+1','@CMD','  =2','\tword','\rword','\nword'])assert.equal(safeCell(text),"'"+text);
 const expected=normalize([{id:'X',deliverable:'=HYPERLINK("https://invalid")',owner:'  +formula'}]);
 const restored=parseCSV(csvFor(expected));assert.ok(restored.rows[0].deliverable.startsWith("'="));assert.ok(restored.rows[0].owner.startsWith("'  +"));
 assert.deepEqual(parseFile(JSON.stringify(documentFor(expected)),'register.json'),expected);
});
test('malformed, ambiguous and duplicate inputs fail without dropping content',()=>{
 for(const input of ['id,deliverable\nX,"missing','id,deliverable\nX,a,b','id,id,deliverable\nX,X,a','id,deliverable\nX,"a"tail','id,deliverable\nX,a\nX,b','id,deliverable,unexpected\nX,a,z'])assert.throws(()=>parseCSV(input));
 for(const rows of [[{id:'X',deliverable:'a',status:'Approved'}],[{id:'X',deliverable:'a',due_date:'2026-02-30'}],[{id:'X',deliverable:'a',owner:8}],[{id:'X',deliverable:'a',custom:'do not silently lose'}],[{id:' ',deliverable:'a'}]])assert.throws(()=>normalize(rows));
});
test('metadata cannot imply approval and study labels cannot silently conflict',()=>{
 assert.throws(()=>parseCSV('study_label,id,deliverable\nA,X,a\nB,Y,b'));
 assert.throws(()=>normalize({schema:1,kind:'toolkit-pipeline-register',study:'',rows:[],approved:true}));
 const doc=documentFor(state);assert.match(doc.notice,/not a scientific approval/);assert.ok(!('approved' in doc));
});
