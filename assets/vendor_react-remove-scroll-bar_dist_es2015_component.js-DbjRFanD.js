import{r as s}from"./vendor_react_index.js_commonjs-es-import-Dw0Sl0kA.js";import{s as f}from"./vendor_react-style-singleton_dist_es2015_component.js-BsvILp-f.js";import{n as p,z as g,f as l,r as v}from"./vendor_react-remove-scroll-bar_dist_es2015_constants.js-CLVUxYvc.js";import{g as m}from"./vendor_react-remove-scroll-bar_dist_es2015_utils.js-Dw7g1_eY.js";var b=f(),r="data-scroll-locked",h=function(n,e,o,t){var a=n.left,i=n.top,u=n.right,c=n.gap;return o===void 0&&(o="margin"),`
  .`.concat(p,` {
   overflow: hidden `).concat(t,`;
   padding-right: `).concat(c,"px ").concat(t,`;
  }
  body[`).concat(r,`] {
    overflow: hidden `).concat(t,`;
    overscroll-behavior: contain;
    `).concat([e&&"position: relative ".concat(t,";"),o==="margin"&&`
    padding-left: `.concat(a,`px;
    padding-top: `).concat(i,`px;
    padding-right: `).concat(u,`px;
    margin-left:0;
    margin-top:0;
    margin-right: `).concat(c,"px ").concat(t,`;
    `),o==="padding"&&"padding-right: ".concat(c,"px ").concat(t,";")].filter(Boolean).join(""),`
  }
  
  .`).concat(g,` {
    right: `).concat(c,"px ").concat(t,`;
  }
  
  .`).concat(l,` {
    margin-right: `).concat(c,"px ").concat(t,`;
  }
  
  .`).concat(g," .").concat(g,` {
    right: 0 `).concat(t,`;
  }
  
  .`).concat(l," .").concat(l,` {
    margin-right: 0 `).concat(t,`;
  }
  
  body[`).concat(r,`] {
    `).concat(v,": ").concat(c,`px;
  }
`)},d=function(){var n=parseInt(document.body.getAttribute(r)||"0",10);return isFinite(n)?n:0},x=function(){s.useEffect(function(){return document.body.setAttribute(r,(d()+1).toString()),function(){var n=d()-1;n<=0?document.body.removeAttribute(r):document.body.setAttribute(r,n.toString())}},[])},R=function(n){var e=n.noRelative,o=n.noImportant,t=n.gapMode,a=t===void 0?"margin":t;x();var i=s.useMemo(function(){return m(a)},[a]);return s.createElement(b,{styles:h(i,!e,a,o?"":"!important")})};export{R};
//# sourceMappingURL=vendor_react-remove-scroll-bar_dist_es2015_component.js-DbjRFanD.js.map
