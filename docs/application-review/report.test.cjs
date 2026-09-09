const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const scope = {};
vm.runInNewContext(html.match(/<script id="review-model">([\s\S]*?)<\/script>/)[1], scope);
const { filterFindings, selectedFindings } = scope.Review;
const items = [
 {id:'UX-1', category:'UX', priority:'P1', title:'Recover text', surface:'Delivery', detail:'Retain raw transcript', effort:'M'},
 {id:'DS-1', category:'Design', priority:'P2', title:'Overlay placement', surface:'Recording', detail:'Match location copy', effort:'S'},
 {id:'FT-1', category:'Features', priority:'P1', title:'Local-only mode', surface:'Setup', detail:'Control cloud fallback', effort:'M'}
];
test('search matches evidence text case-insensitively', () => {
 assert.deepEqual(Array.from(filterFindings(items, {query:'RAW TRANSCRIPT'}), x=>x.id), ['UX-1']);
});
test('category, priority and search combine', () => {
 assert.deepEqual(Array.from(filterFindings(items, {category:'Features', priority:'P1', query:'cloud'}), x=>x.id), ['FT-1']);
 assert.equal(filterFindings(items, {category:'UX', priority:'P2'}).length, 0);
});
test('blank filters show all findings, urgency sort is stable', () => {
 assert.deepEqual(Array.from(filterFindings([items[1],items[0],items[2]], {}), x=>x.id), ['UX-1','FT-1','DS-1']);
});
test('no-match search returns an empty set', () => {
 assert.equal(filterFindings(items, {query:'nonexistentterm'}).length, 0);
});
test('shortlist exports only known selected findings in document order', () => {
 assert.deepEqual(Array.from(selectedFindings(items, ['FT-1','UX-1','gone']), x=>x.id), ['UX-1','FT-1']);
});
test('published report has unique findings and valid local evidence anchors', () => {
 const data = JSON.parse(html.match(/<script id="review-data" type="application\/json">([\s\S]*?)<\/script>/)[1]);
 assert.ok(data.length >= 24, 'Detailed three-track review contains at least 24 findings');
 assert.equal(new Set(data.map(x=>x.id)).size, data.length);
 for (const item of data) {
  for (const key of ['id','category','priority','title','surface','detail','recommendation','acceptance','effort','confidence']) assert.ok(item[key], `${item.id}: ${key}`);
  assert.ok(item.evidence.length, `${item.id}: evidence`);
  for (const ref of item.evidence) {
   const target = path.resolve(__dirname, '../..', ref.path);
   const lines = fs.readFileSync(target,'utf8').split('\n');
   assert.ok(ref.line > 0 && ref.line <= lines.length, `${item.id}: ${ref.path}:${ref.line}`);
  }
 }
});

// Executes the report's actual inline controller with a minimal DOM fixture.
// This verifies event wiring and state; it does not validate browser rendering.
function preview(stored = '[]', storageFails = false) {
 const ids = {}, downloads = [], events = {}, storage = new Map([['mini-whisper-review-2026-09-09',stored]]);
 let cards = [];
 class Element {
  constructor(id='') { this.id=id;this.value='';this.checked=false;this.hidden=false;this.dataset={};this.attributes={};this.listeners={};this.open=false;this.textContent=''; }
  addEventListener(name, fn) { this.listeners[name]=fn; }
  setAttribute(k,v) { this.attributes[k]=String(v); }
  removeAttribute(k) { delete this.attributes[k]; }
  focus() { this.focused=true; }
  scrollIntoView() { this.scrolled=true; }
  closest(selector) { return selector==='[data-save]' && this.dataset.save ? this : null; }
  querySelector(selector) { return selector==='summary' ? this.summary : null; }
  click() { if(this.download) downloads.push(this);this.fire('click'); }
  fire(name='click', target=this) { this.listeners[name]?.({target}); }
  get innerHTML() { return this.markup || ''; }
  set innerHTML(value) {
   this.markup=value;
   if(this.id!=='findings')return;
   for(const card of cards)delete ids[card.id];
   cards=[...value.matchAll(/<details class="finding" id="([^"]+)"\s*(open)?/g)].map(m=>{
    const card=new Element(m[1]);card.open=!!m[2];card.summary=new Element();card.save=new Element();card.save.dataset.save=card.id;ids[card.id]=card;return card;
   });
  }
 }
 for(const id of ['main','search','category','priority','shortlist-only','shortlist-count','export','reset','expand','findings','result-count','status','print','nav-count','step-detail','review-data','journey-data'])ids[id]=new Element(id);
 ids.category.value=ids.priority.value='all';
 for(const id of ['review-data','journey-data'])ids[id].textContent=html.match(new RegExp(`<script id="${id}" type="application/json">([\\s\\S]*?)</script>`))[1];
 const nav=['findings','journey','language','roadmap','scope'].map(name=>{const el=new Element();el.dataset.view=name;ids['view-'+name]=new Element('view-'+name);return el;});
 const steps=[0,1,2,3,4].map(i=>{const el=new Element();el.dataset.step=String(i);return el;});
 const focus=['UX-01','UX-03','DS-01'].map(id=>{const el=new Element();el.dataset.focus=id;return el;});
 const document={getElementById:id=>ids[id],createElement:()=>new Element(),querySelectorAll:selector=>{
  if(selector==='nav button')return nav;
  if(selector==='.view')return nav.map(n=>ids['view-'+n.dataset.view]);
  if(selector==='.finding')return cards;
  if(selector==='.finding[open]')return cards.filter(c=>c.open);
  if(selector==='[data-step]')return steps;
  if(selector==='[data-focus]')return focus;
  throw Error('Unexpected selector '+selector);
 },querySelector:selector=>cards.find(c=>selector===`[data-save="${c.id}"]`)?.save};
 const blobs=[];
 const runtime={document,localStorage:{getItem:k=>{if(storageFails)throw Error('storage blocked');return storage.get(k);},setItem:(k,v)=>{if(storageFails)throw Error('storage blocked');storage.set(k,v);}},window:{addEventListener:(k,v)=>events[k]=v,print(){}},Blob:class {constructor(parts){this.parts=parts;blobs.push(this);}},URL:{createObjectURL:()=> 'blob:test',revokeObjectURL(){}},setTimeout:fn=>fn()};
 vm.createContext(runtime);
 for(const match of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)) if(!match[1].includes('application/json'))vm.runInContext(match[2],runtime);
 return {ids,nav,steps,focus,storage,downloads,blobs,events,get cards(){return cards;},save(id){const card=ids[id];card.open=true;ids.findings.fire('click',card.save);}};
}
test('controller combines controls, shows empty state and resets filters', () => {
 const p=preview(); assert.equal(p.cards.length,33);
 p.ids.category.value='Features';p.ids.category.fire('change');assert.equal(p.cards.length,10);
 p.ids.priority.value='P3';p.ids.priority.fire('change');assert.deepEqual(p.cards.map(x=>x.id),['FT-10']);
 p.ids.search.value='unmatchable-string';p.ids.search.fire('input');assert.equal(p.cards.length,0);assert.match(p.ids.findings.innerHTML,/No matching findings/);
 p.ids.reset.click();assert.equal(p.cards.length,33);
});
test('shortlist persists, filters and exports the selected content', () => {
 const p=preview();p.save('UX-01');assert.equal(p.ids.export.disabled,false);
 assert.match(p.storage.values().next().value,/UX-01/);
 p.ids['shortlist-only'].checked=true;p.ids['shortlist-only'].fire('change');assert.deepEqual(p.cards.map(c=>c.id),['UX-01']);
 p.ids.export.click();assert.equal(p.downloads[0].download,'mini-whisper-review-shortlist.md');assert.match(p.blobs[0].parts.join(''),/Keep recognized text/);assert.doesNotMatch(p.blobs[0].parts.join(''),/## FT-10/);
 const reloaded=preview(p.storage.values().next().value);assert.equal(reloaded.ids['shortlist-count'].textContent,'(1)');
});
test('unavailable or malformed storage does not break the report', () => {
 const p=preview('{malformed',true);assert.equal(p.cards.length,33);p.save('UX-01');assert.match(p.ids.status.textContent,/storage is unavailable/);
 assert.equal(preview('{}').ids['shortlist-count'].textContent,'(0)');
});
test('navigation switches sections and starts at the main content', () => {
 const p=preview();p.nav[2].click();assert.equal(p.ids['view-language'].hidden,false);assert.equal(p.ids['view-findings'].hidden,true);assert.equal(p.nav[2].attributes['aria-current'],'page');
 assert.equal(p.ids.main.scrolled,true);
});
test('journey stages display their own evidence-linked recommendations', () => {
 const p=preview();p.steps[3].click();assert.match(p.ids['step-detail'].innerHTML,/Confirm|Deliver/);assert.match(p.ids['step-detail'].innerHTML,/FT-09/);assert.equal(p.steps[3].attributes['aria-pressed'],'true');assert.equal(p.steps[0].attributes['aria-pressed'],'false');
});
test('priority links clear filters and open the named finding', () => {
 const p=preview();p.ids.category.value='Features';p.ids.category.fire('change');p.focus[0].click();assert.equal(p.ids.category.value,'all');assert.equal(p.ids['UX-01'].open,true);assert.equal(p.ids['UX-01'].scrolled,true);
});
test('expand toggles all current results', () => {
 const p=preview();p.ids.expand.click();assert.ok(p.cards.every(c=>c.open));p.ids.expand.click();assert.ok(p.cards.every(c=>!c.open));
});
test('print expands the complete review and restores filters afterward', () => {
 const p=preview();p.ids.category.value='Features';p.ids.category.fire('change');p.ids['FT-01'].open=true;p.events.beforeprint();assert.equal(p.cards.length,33);assert.ok(p.cards.every(c=>c.open));p.events.afterprint();assert.equal(p.cards.length,10);assert.equal(p.ids['FT-01'].open,true);assert.equal(p.ids['FT-02'].open,false);
});
