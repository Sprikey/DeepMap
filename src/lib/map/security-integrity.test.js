// @ts-expect-error Node-only test: no Node ambient types in this repo.
import test from 'node:test';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import assert from 'node:assert/strict';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { readFileSync } from 'node:fs';
// @ts-expect-error Node-only test: no Node ambient types in this repo.
import { runInNewContext } from 'node:vm';
import { markerIdKey } from '../editor/marker-editor.js';
import { normalizeFileReference } from '../storage/references.js';
import { resolveFileUrl } from '../storage/resolve.js';
import { loadEditorMarkerContent } from '../editor/marker-content.js';
import { createEditorCategory } from '../editor/category-editor.js';

/** @param {string} path */
const read = path => readFileSync(new URL(path, import.meta.url), 'utf8').replace(/\r/g, '');
const mapSource = read('./map-data.js').replace(/^import .*;$/gm, '').replace(/export /g, '');
/** @param {Record<string, any[]>} responses */
function database(responses) {
    const calls = /** @type {{table: string, key: string, ids: any[]}[]} */([]);
    return { calls, from(/** @type {string} */ table) {
        const builder = {
            select() { return this; }, order() { return this; },
            eq(/** @type {string} */ key, /** @type {any} */ id) { calls.push({table,key,ids:[id]}); return this; },
            in(/** @type {string} */ key, /** @type {any[]} */ ids) { calls.push({table,key,ids}); return this; },
            then(/** @type {any} */ resolve) { return Promise.resolve({data:responses[table]??[],error:null}).then(resolve); }
        };
        return builder;
    }};
}
function attachments() {
    return runInNewContext(mapSource + '\n({images:attachMarkerImages,content:attachMarkerContent,layer:normaliseLayer,category:normaliseCategory,markerImage:normaliseMarkerImage})', {
        bigintIdKey:markerIdKey, normalizeFileReference, resolveFileUrl, console:{warn(){}}
    });
}
const first = '9007199254740992', second = '9007199254740993';
test('public layer, category and marker image readers preserve URLs and keep R2 unavailable', () => {
    const api = attachments();
    for (const source of ['static', 'external', 'r2', 'none', undefined]) {
        const ref = source === 'external' ? 'http://example.test/a%2Fb?q=1' : '/same%20path.webp';
        const expected = source === 'r2' ? null : ref;
        assert.equal(api.layer({ image_source: source, image_ref: ref }).image, expected);
        assert.equal(api.category({ icon_source: source, icon_ref: ref }).icon, expected);
        assert.equal(api.markerImage({ source, image_ref: ref }).url, expected);
    }
    assert.equal(api.layer({ image_source: 'static', image_ref: null }).image, null);
});
test('public attachments retain adjacent BIGINT marker and section identities', async()=>{
    const db=database({
        marker_images:[{id:1,marker_id:first,source:'external',image_ref:'https://example.test/a'}, {id:2,marker_id:second,source:'external',image_ref:'https://example.test/b'}],
        marker_sections:[{id:first,marker_id:first,section_type:'note'}, {id:second,marker_id:second,section_type:'item'}],
        marker_section_rows:[{id:1,section_id:first,text_en:'A'}, {id:2,section_id:second,text_en:'B'}]
    });
    const api=attachments(), locations=[{databaseId:first},{databaseId:second}];
    const images=await api.images({supabase:db,locations});
    assert.equal(images[0].images[0].url,'https://example.test/a');
    assert.equal(images[1].images[0].url,'https://example.test/b');
    const content=await api.content({supabase:db,locations});
    assert.equal(content[0].contentItems[0].text.en,'A');assert.equal(content[1].contentItems[0].text.en,'B');
    for(const call of db.calls) assert.deepEqual(Array.from(call.ids),[first,second]);
});
test('numeric safe marker IDs match string foreign keys without coercion loss',async()=>{
    const db=database({marker_images:[{id:1,marker_id:'7',source:'static',image_ref:'/a.png'}]});
    const result=await attachments().images({supabase:db,locations:[{databaseId:7}]});
    assert.equal(result[0].images[0].url,'/a.png');
    assert.deepEqual(Array.from(db.calls[0].ids),['7']);
});
for(const kind of ['images','content']) test('public '+kind+' rejects an unrelated marker response',async()=>{
    const db=database({marker_images:[{id:1,marker_id:'8'}],marker_sections:[{id:1,marker_id:'8'}]});
    const locations=[{databaseId:'7'}];
    assert.equal(await attachments()[kind]({supabase:db,locations}),locations);
});
test('public content rejects a row from an unrequested section',async()=>{
    const db=database({marker_sections:[{id:'7',marker_id:'1'}],marker_section_rows:[{section_id:'8',text_en:'wrong'}]});
    const locations=[{databaseId:'1'}];
    assert.equal(await attachments().content({supabase:db,locations}),locations);
});
test('editor quick content retains adjacent BIGINT section identities',async()=>{
    const db=database({
        marker_sections:[{id:first,section_type:'note',metadata:{editor:'quick-content-v1'}},{id:second,section_type:'item',metadata:{editor:'quick-content-v1'}}],
        marker_section_rows:[{section_id:first,text_en:'A'},{section_id:second,text_en:'B'}]
    });
    const result=await loadEditorMarkerContent({supabase:db,markerId:'1'});
    assert.deepEqual(result.map((/** @type {any} */ row)=>row.type),['note','item']);
});
test('Leaflet tooltip receives escaped title rather than executable HTML',()=>{
    const source=read('./GameMapPage.svelte');
    const escape=source.slice(source.indexOf('    function escapeHtml('),source.indexOf('    function translateList('));
    const render=source.slice(source.indexOf('    function renderLocationMarkers('),source.indexOf('    function createMapLabelIcon('));
    let tooltip='';
    const location={databaseId:'7',mapLayer:'surface',categoryId:'test',coordinates:[0,0]};
    const marker={bindPopup(){},bindTooltip(/** @type {string} */ html){tooltip=html;},on(){},addTo(){}};
    const title='<img src=x onerror="globalThis.compromised=true"> & test';
    runInNewContext(escape+render+'\nrenderLocationMarkers();',{
        map:{},Leaflet:{marker:()=>marker},markerLayerGroups:{surface:{clearLayers(){}}},locations:[location],
        categoryVisibility:{},getCategoryForRender:()=>({}),editorMode:false,createLocationIcon:()=>({}),
        buildLocationPopup:()=>'',getLocationTitle:()=>title,markerIdKey
    });
    assert.equal(tooltip,'&lt;img src=x onerror=&quot;globalThis.compromised=true&quot;&gt; &amp; test');
});

test('category create carries UUID so the bridge rejects another game alias before writing',async()=>{
    const gameA='10000000-0000-0000-0000-000000000001';
    const gameB='10000000-0000-0000-0000-000000000002';
    let writes=0;
    const db=/** @type {any} */({from(){return {insert(/** @type {any} */ payload){
        // Model the existing B2b/B6b authoritative BEFORE INSERT bridge.
        const mappedUuid=payload.game_id==='game-b'?gameB:gameA;
        return {select(){return this;},async single(){
            if(payload.game_uuid && payload.game_uuid!==mappedUuid)
                return {data:null,error:new Error('B2B_CATEGORY_LEGACY_GAME_UUID_MISMATCH')};
            writes++;
            return {data:{...payload,game_uuid:mappedUuid,category_uuid:gameA,group_uuid:null},error:null};
        }};
    }}}});
    const category={id:'test',groupUuid:null,nameEn:'Test',namePt:'Teste'};
    await assert.rejects(createEditorCategory({supabase:db,gameUuid:gameA,legacyGameId:'game-b',category}),/LEGACY_GAME_UUID_MISMATCH/);
    assert.equal(writes,0);
    const saved=await createEditorCategory({supabase:db,gameUuid:gameA,legacyGameId:'game-a',category});
    assert.equal(saved.game_uuid,gameA);assert.equal(writes,1);
});
