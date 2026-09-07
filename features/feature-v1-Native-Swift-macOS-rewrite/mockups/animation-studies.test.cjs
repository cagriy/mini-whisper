const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(`${__dirname}/mockup-v1-animation-studies.html`, 'utf8');
const source = html.match(/<script id="motion-model">([\s\S]*?)<\/script>/)?.[1];
assert.ok(source, 'The mockup exposes its self-contained motion model');
const scope = {};
vm.runInNewContext(source, scope);
const { sample, sequenceState, kinds } = scope.Motion;
const extent = points => points.reduce((sum, p) => sum + (p.x-150)**2 + (p.y-140)**2 + (p.h || 0)**2, 0) / points.length;

test('five retained alternatives plus the current constellation', () => {
  assert.deepEqual(Array.from(kinds), ['current','ribbon','halo','bars','pearl','aperture']);
});
test('every alternative visibly responds to speech intensity', () => {
  for (const kind of kinds.filter(k => k !== 'current')) {
    assert.ok(extent(sample(kind, 1.3, 1, 'speaking')) > extent(sample(kind, 1.3, 0, 'speaking')) * 1.08, kind);
  }
});
test('processing ignores speech intensity and stays animated', () => {
  for (const kind of kinds) {
    assert.deepEqual(sample(kind, 2, 0, 'processing'), sample(kind, 2, 1, 'processing'), kind);
    assert.notDeepEqual(sample(kind, 2, 0, 'processing'), sample(kind, 3, 0, 'processing'), kind);
  }
});
test('quiet ignores the speech slider, completion settles', () => {
  for (const kind of kinds) {
    assert.deepEqual(sample(kind, 1, 0, 'quiet'), sample(kind, 1, 1, 'quiet'));
    assert.deepEqual(sample(kind, 1, 0, 'done'), sample(kind, 20, 1, 'done'));
  }
});
test('all states produce finite geometry inside the overlay', () => {
  for (const kind of kinds) for (const state of ['quiet', 'speaking', 'processing', 'done']) {
    for (const t of [0, 1.3, 20, 500]) for (const level of [0, 0.5, 1]) {
      const points = sample(kind, t, level, state);
      assert.ok(points.length > 0);
      for (const p of points) {
        assert.ok(Object.values(p).every(Number.isFinite), `${kind} ${state}`);
        if (kind !== 'current') assert.ok(p.x >= 5 && p.x <= 295 && p.y >= 5 && p.y <= 275, `${kind} stays in frame`);
      }
    }
  }
});
test('demo covers the recording lifecycle and loops', () => {
  assert.equal(sequenceState(0), 'quiet');
  assert.equal(sequenceState(3), 'speaking');
  assert.equal(sequenceState(9), 'processing');
  assert.equal(sequenceState(12), 'done');
  assert.equal(sequenceState(14), 'quiet');
});

// Exercise the actual inline controller with a minimal DOM/canvas fixture.
function preview() {
  class Element {
    constructor(value='') { this.value=value; this.dataset={};this.style={};this.listeners={};this.attributes={};this.children=[];this.checked=false; }
    addEventListener(event,fn) { this.listeners[event]=fn; }
    setAttribute(k,v) { this.attributes[k]=v; }
    append(el) { this.children.push(el); }
    querySelector(key) { return this.parts[key]; }
    fire(event='click') { this.listeners[event]?.({}); }
    set innerHTML(value) {
      this.parts={};
      for(const key of ['canvas','select','.overlay-label','.state-name','.state-detail'])this.parts[key]=new Element(key==='select'?'follow':'');
      const canvas=this.parts.canvas;canvas.ops=[];
      const ctx=new Proxy({}, {get:(_,key)=> key==='clearRect'?()=>{canvas.ops=[]}: key==='createRadialGradient'?()=>({addColorStop(){}}): (...args)=>canvas.ops.push([key,...args]),set:()=>true});
      canvas.getContext=()=>ctx;
    }
  }
  const ids={};for(const id of ['studies','reduce','play','pause','intensity','intensity-value','phrases','signal','backdrop','progress'])ids[id]=new Element();
  ids.phrases.checked=true;ids.intensity.value='65';
  const buttons=['quiet','speaking','processing','done'].map(s=>{const b=new Element();b.dataset.state=s;return b;});
  let nextFrame;
  const scope={document:{hidden:false,documentElement:new Element(),getElementById:id=>ids[id],querySelectorAll:()=>buttons,createElement:()=>new Element()},matchMedia:()=>({matches:false,addEventListener(){}}),requestAnimationFrame:fn=>{nextFrame=fn;}};
  for(const script of html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g))vm.runInNewContext(script[1],scope);
  let now=0;
  return {ids,buttons,cards:ids.studies.children,frame(n=1){for(let i=0;i<n;i++){now+=16;nextFrame(now);}}};
}
test('state controls update every card and disable irrelevant voice controls', () => {
  const p=preview();p.frame(30);p.buttons[2].fire();p.frame();
  assert.equal(p.ids.intensity.disabled,true);
  for(const card of p.cards)assert.equal(card.parts['.state-name'].textContent,'Processing');
  const pearl=p.cards.find(c=>c.dataset.kind==='pearl');
  const select=pearl.parts.select;select.value='speaking';select.fire('change');p.frame();
  assert.equal(p.ids.intensity.disabled,false);
  assert.equal(pearl.parts['.state-name'].textContent,'Speaking');
  assert.equal(p.cards[0].parts['.state-name'].textContent,'Processing');
});
test('pause freezes geometry, but selecting another state still previews that state', () => {
  const p=preview();p.frame(60);p.ids.pause.fire();p.frame();
  const canvas=p.cards[1].parts.canvas;
  const frozen=JSON.stringify(canvas.ops);p.frame(10);assert.equal(JSON.stringify(canvas.ops),frozen);
  p.buttons[2].fire();p.frame();assert.notEqual(JSON.stringify(canvas.ops),frozen);
});
test('reduced motion stays static and the sequence moves through processing', () => {
  const p=preview();p.ids.reduce.checked=true;p.ids.reduce.fire('change');p.frame(10);
  const pearl=p.cards.find(c=>c.dataset.kind==='pearl');
  const canvas=pearl.parts.canvas,still=JSON.stringify(canvas.ops);p.frame(10);assert.equal(JSON.stringify(canvas.ops),still);
  p.ids.play.fire();p.frame(570);assert.equal(pearl.parts['.state-name'].textContent,'Processing');
});
test('only retained cards render and independently preview every state', () => {
  const p=preview();
  assert.deepEqual(p.cards.map(c=>c.dataset.kind), ['current','ribbon','halo','bars','pearl','aperture']);
  p.frame(5);
  for(const card of p.cards) {
    for(const state of ['quiet','speaking','processing','done']) {
      card.parts.select.value=state;card.parts.select.fire('change');p.frame(2);
      assert.equal(card.parts['.state-name'].textContent, {quiet:'Quiet',speaking:'Speaking',processing:'Processing',done:'Complete'}[state]);
      assert.ok(card.parts.canvas.ops.some(op=>op[0]==='stroke'||op[0]==='fill'), `${card.dataset.kind}: visible ${state}`);
    }
  }
});
