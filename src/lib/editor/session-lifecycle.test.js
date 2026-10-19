// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { readFileSync } from 'node:fs';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { runInNewContext } from 'node:vm';
import { parse } from 'svelte/compiler';
import { createSessionScope } from '../auth/session-scope.js';
import { replaceEditorMarkerContent } from './marker-content.js';
import { setMarkerImageCover, moveMarkerImage } from './marker-image-editor.js';
import { createEditorCategory, deleteEditorCategory } from './category-editor.js';
import { createEditorMapLabel, updateEditorMapLabel, deleteEditorMapLabel } from './map-label-editor.js';

const gameUuid = '10000000-0000-0000-0000-000000000001';
const gameMapUuid = '20000000-0000-0000-0000-000000000002';
const layerUuid = '30000000-0000-0000-0000-000000000003';
const categoryUuid = '40000000-0000-0000-0000-000000000004';
function deferred() {
    let resolve = /** @type {(value: any) => void} */ (() => {});
    const promise = new Promise(r => { resolve = r; });
    return { promise, resolve };
}
/** @param {any} [rpc] */
function client(rpc = async () => ({data: [], error: null})) {
    let callback = /** @type {any} */ (null); let stopped = false;
    return { rpc, auth: {
        onAuthStateChange(/** @type {any} */ fn) { callback = fn; return { data: { subscription: { unsubscribe() { stopped = true; } } } }; },
        getUser: async () => ({data: {user: {id: 'a'}}, error: null})
    }, emit(/** @type {string | null} */ id, event = 'SIGNED_IN') { return callback(event, id ? {user: {id}} : null); },
    get stopped() { return stopped; } };
}
/** Actual component script with live derived getters; effects flushed explicitly.
 * @param {string} name @param {any} db @param {any} [extra] @returns {any}
 */
function harness(name, db, extra = {}) {
    const source = readFileSync(new URL(name + '.svelte', import.meta.url), 'utf8').replace(/\r/g, '');
    const ast = /** @type {any} */ (parse(source, {modern: true}));
    let script = source.slice(0, ast.instance.content.end);
    for (const node of [...ast.instance.content.body].reverse()) {
        if (node.type === 'ImportDeclaration') script = script.slice(0,node.start) + script.slice(node.end);
        else if (node.type === 'VariableDeclaration') {
            const d = node.declarations[0], call = d.init;
            if (call?.type !== 'CallExpression') continue;
            const by = call.callee.type === 'MemberExpression' && call.callee.object.name === '$derived';
            if (call.callee.name !== '$derived' && !by) continue;
            const arg = call.arguments[0], expr = source.slice(arg.start, arg.end);
            script = script.slice(0,node.start) + `Object.defineProperty(globalThis, '${d.id.name}', {get: () => (${expr})${by?'()':''}});` + script.slice(node.end);
        }
    }
    script = script.slice(script.indexOf('<script>') + 8).replace(/export function /g, 'function ');
    const mounts = /** @type {any[]} */ ([]), effects = /** @type {any[]} */ ([]), cleanups = /** @type {any[]} */ ([]);
    const timers = new Map(); let timerId = 0;
    const listeners = new Map();
    const eventTarget = {addEventListener: (/** @type {string} */ key, /** @type {any} */ fn) => listeners.set(key, fn),
        removeEventListener: (/** @type {string} */ key) => listeners.delete(key)};
    const props = {active:true, gameUuid, gameMapUuid, legacyGameId:'legacy', markerId:'7', standalone:true,
        gameContext: {gameUuid,gameMapUuid}, renderer: {defaultLayerKey:'surface',translations:{en:{}},fallback:{categories:{},categoryGroups:[],locations:[],mapLabels:[],mapDefinitions:{}}}};
    const context = {getSupabaseBrowserClient:()=>db, createSessionScope,
        onMount: (/** @type {any} */ fn)=>mounts.push(fn), $effect:(/** @type {any} */ fn)=>effects.push(fn),
        untrack:(/** @type {any} */ fn)=>fn(), tick:async()=>{},
        $state:(/** @type {any} */ value)=>value, $props:()=>props,
        setTimeout:(/** @type {any} */ fn)=>{timers.set(++timerId,fn);return timerId;},
        clearTimeout:(/** @type {any} */ id)=>timers.delete(id),
        requestAnimationFrame:(/** @type {any} */ fn)=>{timers.set(++timerId,fn);return timerId;},cancelAnimationFrame:(/** @type {any} */ id)=>timers.delete(id),
        window:{...eventTarget,location:{search:''},matchMedia:()=>({...eventTarget,matches:false})}, document:eventTarget,
        URLSearchParams, AbortController, requireRendererLegacyGameId:()=> 'legacy',
        resolveMarkerImageUrl:()=>null, getVideoEmbedUrl:()=>null,normaliseHttpUrl:()=>null,
        markerIdKey:String,sameMarkerId:(/** @type {any} */ a,/** @type {any} */ b)=>String(a)===String(b),
        console:{error(){},warn(){},info(){}}, ...extra };
    const api = runInNewContext(script + '\n({read: (code) => eval(code), run: (code) => eval(code)})', context);
    // Map's second mount starts Leaflet; never run that browser-only import here.
    for(const fn of name.includes('GameMapPage')?mounts.slice(0,1):mounts) cleanups.push(fn());
    function flush() { cleanups.splice(mounts.length).forEach(fn=>fn?.()); for(const fn of effects) cleanups.push(fn()); }
    return {api,flush,timers,listeners,cleanup(){for(const fn of cleanups.reverse())fn?.();}};
}

for(const next of [null,'b']) test('session epoch invalidates captures on '+String(next),()=>{
    const db=client();let changes=0;const scope=createSessionScope(()=>{changes++;});
    const stop=scope.start(/** @type {any} */(db));assert.equal(scope.capture()(),false);
    assert.equal(db.emit('a','INITIAL_SESSION'),undefined);const current=scope.capture();assert.equal(current(),true);
    db.emit(next,'TOKEN_REFRESHED');assert.equal(current(),false);assert.equal(changes,2);
    const latest=scope.capture();stop();assert.equal(latest(),false);assert.equal(db.stopped,true);
    db.emit('b');assert.equal(changes,2);
});

for(const next of [null,'b','unmount']) test('user list suppresses late response after '+next,async()=>{
    const pending=deferred();const db=client(()=>pending.promise);const h=harness('UserManagementPanel',db);
    db.emit('a');const read=h.api.run('loadUsers()');
    if(next==='unmount')h.cleanup();else db.emit(next);
    pending.resolve({data:[{user_id:'old',total_count:1}],error:null});await read;
    assert.equal(h.api.read('users.length'),0);assert.equal(h.api.read('total'),0);
    if(next!=='unmount')h.cleanup();
});

test('user list latest filter wins; old finally does not clear newer loading',async()=>{
    const a=deferred(),b=deferred();let n=0;
    const db=client(()=>++n===1?a.promise:b.promise);const h=harness('UserManagementPanel',db);db.emit('a');
    const old=h.api.run('loadUsers()');h.api.run("roleFilter='moderator'");const latest=h.api.run('loadUsers()');
    a.resolve({data:[{user_id:'old'}],error:null});await old;assert.equal(h.api.read('loading'),true);
    b.resolve({data:[{user_id:'new',total_count:1}],error:null});await latest;
    assert.equal(h.api.read('users[0].id'),'new');assert.equal(h.api.read('loading'),false);h.cleanup();
});

test('user action after session replacement cannot refresh or report success',async()=>{
    const pending=deferred();let calls=0;
    const db=client(()=>{calls++;return pending.promise;});const h=harness('UserManagementPanel',db,{window:{confirm:()=>true}});
    db.emit('a');h.api.run("users=[{id:'target',role:'user'}]");const work=h.api.run('toggleModerator(users[0])');
    db.emit('b');pending.resolve({error:null});await work;
    assert.equal(calls,1);assert.equal(h.api.read('successMessage'),'');assert.equal(h.api.read('workingId'),null);h.cleanup();
});

for(const next of ['b','unmount','selection']) test('image mutation continuation owned across '+next,async()=>{
    const upload=deferred();let writes=0,reads=0;const db=client();
    const h=harness('MarkerImagesPanel',db,{createMarkerImage:()=>{writes++;return upload.promise;},loadMarkerImages:async()=>{reads++;return [];}});
    db.emit('a');h.api.run("imageRef='https://example.test/image.png'");const work=h.api.run('addImage()');
    if(next==='unmount')h.cleanup();else if(next==='selection')h.api.run("markerId='8'");else db.emit(next);
    upload.resolve({id:'old'});await work;assert.equal(writes,1);assert.equal(reads,0);
    assert.equal(h.api.read('errorMessage'),'');if(next!=='unmount')h.cleanup();
});

test('image reads do not replace newly selected marker/loading',async()=>{
    const first=deferred(),second=deferred();let n=0;const db=client();
    const h=harness('MarkerImagesPanel',db,{loadMarkerImages:()=>++n===1?first.promise:second.promise});db.emit('a');
    const old=h.api.run('refresh()');h.api.run("markerId='8'");const latest=h.api.run('refresh()');
    first.resolve([{id:'old'}]);await old;assert.equal(h.api.read('loading'),true);
    second.resolve([{id:'new'}]);await latest;assert.equal(h.api.read('images[0].id'),'new');h.cleanup();assert.equal(db.stopped,true);
});

for(const name of ['MarkerEditorPanel','MapLabelEditorPanel','CategoryManagerPanel'])test(name+' read discarded after session replacement/unmount',async()=>{
    for(const next of ['b','unmount']){
        const pending=deferred();const db=client();
        const h=harness(name,db,{loadEditorMarkers:()=>pending.promise,loadEditorMapLabels:()=>pending.promise,
            loadEditorCategories:()=>pending.promise,loadEditorCategoryGroups:async()=>[]});
        db.emit('a');if(name==='CategoryManagerPanel')h.api.run('expanded=true');
        const work=h.api.run(name==='MarkerEditorPanel'?'refreshMarkers()':name==='MapLabelEditorPanel'?'refresh()':'refreshCategories()');
        if(next==='unmount')h.cleanup();else db.emit(next);
        pending.resolve(name==='CategoryManagerPanel'?[]:{markers:[{id:'old'}],labels:[{id:'old'}],layers:[],categories:[],groups:[]});await work;
        assert.equal(h.api.read(name==='CategoryManagerPanel'?'adminCategories.length':name==='MarkerEditorPanel'?'markers.length':'labels.length'),0);
        assert.equal(h.api.read('editorDataReady'),false);if(next!=='unmount')h.cleanup();
    }
});

/** @param {any[]} responses */
function queries(responses) {
    const calls=/** @type {string[]} */([]);
    const db={from(/** @type {string} */ table){
        const result=responses.shift();let action='read';
        const builder=new Proxy({}, {get(_target,key){
            if(key==='then')return (/** @type {any} */ resolve,/** @type {any} */ reject)=>{calls.push(table+':'+action);return Promise.resolve(result).then(resolve,reject);};
            return ()=>{if(['insert','update','delete'].includes(String(key)))action=String(key);return builder;};
        }});return builder;
    }};
    return {supabase:/** @type {any} */(db),calls};
}

test('content replacement stops between section insert and row write after session replacement',async()=>{
    const pending=deferred();let current=true;const q=queries([{data:[],error:null},pending.promise]);
    const work=replaceEditorMarkerContent({...q,markerId:7,items:[{textEn:'note'}],isCurrent:()=>current});
    for(let i=0;i<20 && q.calls.length<2;i++)await Promise.resolve();
    assert.equal(q.calls.length,2);
    current=false;pending.resolve({data:{id:1},error:null});await assert.rejects(work,/EDITOR_STALE_SESSION/);
    assert.ok(!q.calls.includes('marker_section_rows:insert'));
});

for(const operation of ['cover','reorder'])test(operation+' stops before second write',async()=>{
    const pending=deferred();let current=true;const q=queries([pending.promise]);
    const work=operation==='cover'?setMarkerImageCover({...q,markerId:7,imageId:9,isCurrent:()=>current}):moveMarkerImage({...q,images:[{id:1,sortOrder:10},{id:2,sortOrder:20}],imageId:1,direction:'down',isCurrent:()=>current});
    current=false;pending.resolve({error:null});await assert.rejects(work,/EDITOR_STALE_SESSION/);assert.equal(q.calls.length,1);
});

for(const kind of ['category-create','category-delete','label-create','label-update','label-delete'])test(kind+' does not mutate after stale preflight read',async()=>{
    const pending=deferred();let current=true;const q=queries([pending.promise]);
    const context={...q,gameUuid,gameMapUuid,categoryUuid,selectedLayerUuid:layerUuid,legacyGameId:'legacy',
        labelId:'7',label:{mapLayer:'surface'},category:{id:'test',groupUuid:categoryUuid,nameEn:'Test',namePt:'Teste',color:'#ffffff'},isCurrent:()=>current};
    const work=kind==='category-create'?createEditorCategory(context):kind==='category-delete'?deleteEditorCategory(context):kind==='label-create'?createEditorMapLabel(context):kind==='label-update'?updateEditorMapLabel(context):deleteEditorMapLabel(context);
    current=false;pending.resolve({data:kind==='category-create'?{id:'group',game_id:'legacy',game_uuid:gameUuid,group_uuid:categoryUuid}:kind==='category-delete'?[]:[{id:'surface',game_id:'legacy',game_uuid:gameUuid,game_map_id:gameMapUuid,layer_uuid:layerUuid}],count:0,error:null});
    await assert.rejects(work,/EDITOR_STALE_SESSION/);assert.equal(q.calls.length,1);assert.ok(q.calls.every(c=>c.endsWith(':read')));
});

test('map access cannot restore old admin after auth replacement; listeners/timers cleaned',async()=>{
    const role=deferred();const db=client(()=>role.promise);
    const h=harness('../map/GameMapPage',db);db.emit('a');const work=h.api.run('loadEditorAccess()');
    await Promise.resolve();db.emit('b');role.resolve({data:'admin',error:null});await work;
    assert.equal(h.api.read('isEditorAdmin'),false);assert.equal(h.api.read('currentMapUser'),null);
    h.cleanup();assert.equal(h.listeners.size,0);assert.equal(h.timers.size,0);assert.equal(db.stopped,true);
});

test('map data resolved after route unmount cannot update state',async()=>{
    const pending=deferred();const db=client();const h=harness('../map/GameMapPage',db,{loadDeepMapGameDataWithUuidLayers:()=>pending.promise});
    const work=h.api.run('loadGameMapData()');h.cleanup();pending.resolve({locations:[{id:'old'}]});await work;
    assert.equal(h.api.read('locations.length'),0);
});

test('normal owned user refresh/action succeeds and feedback timer is released',async()=>{
    const db=client(async()=>({data:[{user_id:'target',role:'user',total_count:1}],error:null}));
    const h=harness('UserManagementPanel',db,{window:{confirm:()=>true}});db.emit('a');
    await h.api.run('loadUsers()');await h.api.run('toggleModerator(users[0])');
    assert.ok(h.api.read('successMessage'));assert.equal(h.api.read('workingId'),null);
    await h.api.run('refreshUsers()');assert.equal(h.timers.size,1);h.cleanup();assert.equal(h.timers.size,0);
});

for(const name of ['MapLabelEditorPanel','CategoryManagerPanel'])test(name+' close/reopen releases invalidated busy state',()=>{
    const db=client();const h=harness(name,db,{loadEditorMapLabels:()=>new Promise(()=>{}),
        loadEditorCategories:()=>new Promise(()=>{}),loadEditorCategoryGroups:async()=>[]});
    db.emit('a');h.flush();h.api.run('saving=true;deleting=true');
    h.api.run(name==='MapLabelEditorPanel'?'active=false':'expanded=false');h.flush();
    h.api.run(name==='MapLabelEditorPanel'?'active=true':'expanded=true');h.flush();
    assert.equal(h.api.read('saving'),false);assert.equal(h.api.read('deleting'),false);h.cleanup();
});

test('normal same-session helper chains retain every intended write',async()=>{
    const cover=queries([{error:null},{error:null}]);
    await setMarkerImageCover({...cover,markerId:7,imageId:9,isCurrent:()=>true});assert.equal(cover.calls.length,2);
    const reorder=queries([{error:null},{error:null}]);
    await moveMarkerImage({...reorder,images:[{id:1},{id:2}],imageId:1,direction:'down',isCurrent:()=>true});assert.equal(reorder.calls.length,2);
    const content=queries([{data:[],error:null},{data:{id:1},error:null},{error:null}]);
    await replaceEditorMarkerContent({...content,markerId:7,items:[{textEn:'note'}],isCurrent:()=>true});
    assert.deepEqual(content.calls,['marker_sections:read','marker_sections:insert','marker_section_rows:insert']);
});

test('current map session still receives validated user/admin access',async()=>{
    const db=client(async(/** @type {string} */ name)=>({data:name==='requires_legal_acceptance'?false:'admin',error:null}));const h=harness('../map/GameMapPage',db);
    db.emit('a');await h.api.run('loadEditorAccess()');
    assert.equal(h.api.read('currentMapUser.id'),'a');assert.equal(h.api.read('isEditorAdmin'),true);h.cleanup();
});

for (const response of [{data:true,error:null},{data:null,error:{code:'PGRST202'}}]) test('public map keeps pending/unverified account read-only: '+String(response.data),async()=>{
    const calls=/** @type {string[]} */([]);
    const db=client(async(/** @type {string} */ name)=>{calls.push(name);return name==='requires_legal_acceptance'?response:{data:'admin',error:null};});
    const h=harness('../map/GameMapPage',db);db.emit('a');await h.api.run('loadEditorAccess()');
    assert.equal(h.api.read('currentMapUser'),null);assert.equal(h.api.read('isEditorAdmin'),false);
    assert.ok(!calls.includes('get_deepmap_role'));assert.ok(!calls.includes('is_deepmap_admin'));h.cleanup();
});
for(const event of ['TOKEN_REFRESHED','SIGNED_IN']) test('same account preserves capture after '+event,()=>{
    const db=client();let changes=0;const scope=createSessionScope(()=>{changes++;});
    const stop=scope.start(/** @type {any} */(db));
    db.emit('a','INITIAL_SESSION');const current=scope.capture();
    db.emit('a',event);assert.equal(current(),true);assert.equal(changes,1);
    db.emit(null,'SIGNED_OUT');assert.equal(current(),false);assert.equal(changes,2);
    db.emit('a');assert.equal(current(),false);
    const latest=scope.capture();stop();assert.equal(latest(),false);
});

test('anonymous INITIAL_SESSION initializes once; later account is owned',()=>{
    const db=client();let changes=0;const scope=createSessionScope(()=>{changes++;});
    const stop=scope.start(/** @type {any} */(db));db.emit(null,'INITIAL_SESSION');
    assert.equal(changes,1);assert.equal(scope.capture()(),false);
    db.emit('a');assert.equal(changes,2);assert.equal(scope.capture()(),true);stop();
});

for(const event of ['TOKEN_REFRESHED','SIGNED_IN']) test('map preserves panels/data/revisions after same-account '+event,()=>{
    const db=client();const h=harness('../map/GameMapPage',db);db.emit('a','INITIAL_SESSION');
    h.api.run("editorMode=true;communityPanelOpen=true;locations=[{id:'marker'}];mapLabels=[{id:'label'}];currentMapUser={id:'a'};isEditorAdmin=true");
    const before=h.api.read('[mapSessionRevision,accessRevision,mapDataRevision].join()');
    const timers=h.timers.size;
    db.emit('a',event);
    assert.equal(h.api.read('editorMode && communityPanelOpen && isEditorAdmin'),true);
    assert.equal(h.api.read('locations[0].id'),'marker');assert.equal(h.api.read('mapLabels[0].id'),'label');
    assert.equal(h.api.read('[mapSessionRevision,accessRevision,mapDataRevision].join()'),before);
    assert.equal(h.timers.size,timers);h.cleanup();
});

for(const event of ['TOKEN_REFRESHED','SIGNED_IN']) test('pending user list completes after same-account '+event,async()=>{
    const pending=deferred();const db=client(()=>pending.promise);const h=harness('UserManagementPanel',db);
    db.emit('a');const work=h.api.run('loadUsers()');db.emit('a',event);
    pending.resolve({data:[{user_id:'current',total_count:1}],error:null});await work;
    assert.equal(h.api.read('users[0].id'),'current');assert.equal(h.api.read('total'),1);h.cleanup();
});
