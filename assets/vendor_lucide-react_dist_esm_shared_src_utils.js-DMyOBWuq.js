/**
 * @license lucide-react v0.540.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */const s=t=>t.replace(/([a-z0-9])([A-Z])/g,"$1-$2").toLowerCase(),o=t=>t.replace(/^([A-Z])|[\s-_]+(\w)/g,(e,r,a)=>a?a.toUpperCase():r.toLowerCase()),n=t=>{const e=o(t);return e.charAt(0).toUpperCase()+e.slice(1)},c=(...t)=>t.filter((e,r,a)=>!!e&&e.trim()!==""&&a.indexOf(e)===r).join(" ").trim(),i=t=>{for(const e in t)if(e.startsWith("aria-")||e==="role"||e==="title")return!0};export{n as a,i as h,c as m,s as t};
//# sourceMappingURL=vendor_lucide-react_dist_esm_shared_src_utils.js-DMyOBWuq.js.map
