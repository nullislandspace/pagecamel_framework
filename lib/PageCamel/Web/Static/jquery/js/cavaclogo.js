var projectlogomesh;
var projectlogorenderer;
var projectlogoscene;
var projectlogocamera;

var projectlogovertices = new Array();
projectlogovertices=[
    {x: -100,  y:-50, z: -20}, // back
    {x: -70 ,  y:-50, z: -20},
    {x: -100,  y:50, z: -20},
    {x: -70 ,  y:50, z: -20},
    {x: -70 ,  y:-95, z: -20},
    {x: -70 ,  y:95, z: -20},
    {x: 70 ,  y:-95, z: -20},
    {x: 70 ,  y:-50, z: -20},
    {x: 70 ,  y:95, z: -20},
    {x: 70 ,  y:50, z: -20},
    {x: -100,  y:-50, z: 20}, // front
    {x: -70 ,  y:-50, z: 20},
    {x: -100,  y:50, z: 20},
    {x: -70 ,  y:50, z: 20},
    {x: -70 ,  y:-95, z: 20},
    {x: -70 ,  y:95, z: 20},
    {x: 70 ,  y:-95, z: 20},
    {x: 70 ,  y:-50, z: 20},
    {x: 70 ,  y:95, z: 20},
    {x: 70 ,  y:50, z: 20},
];

var projectlogosurfaces = new Array();
projectlogosurfaces=[ 
    {p1:0, p2:1, p3:2}, // back
    {p1:1, p2:2, p3:3},
    {p1:0, p2:1, p3:4},
    {p1:2, p2:3, p3:5},
    {p1:1, p2:4, p3:6},
    {p1:1, p2:6, p3:7},
    {p1:3, p2:5, p3:8},
    {p1:3, p2:8, p3:9},

    {p1:10, p2:11, p3:12}, // front
    {p1:11, p2:12, p3:13},
    {p1:10, p2:11, p3:14},
    {p1:12, p2:13, p3:15},
    {p1:11, p2:14, p3:16},
    {p1:11, p2:16, p3:17},
    {p1:13, p2:15, p3:18},
    {p1:13, p2:18, p3:19},


    {p1:0, p2:2, p3:10}, // outer sides
    {p1:2, p2:12, p3:10},
    {p1:0, p2:4, p3:14},
    {p1:0, p2:10, p3:14},
    {p1:2, p2:5, p3:15},
    {p1:2, p2:12, p3:15},
    {p1:4, p2:14, p3:6},
    {p1:6, p2:14, p3:16},
    {p1:5, p2:15, p3:8},
    {p1:8, p2:15, p3:18},

    {p1:6, p2:7, p3:16}, // upper flat end
    {p1:7, p2:17, p3:16}, 
    {p1:8, p2:9, p3:18}, // lower flat end
    {p1:9, p2:19, p3:18}, 

    {p1:1, p2:3, p3:13}, // inner sides
    {p1:13, p2:11, p3:1}, 
    {p1:1, p2:7, p3:17},
    {p1:17, p2:11, p3:1}, 
    {p1:3, p2:9, p3:19},
    {p1:19, p2:13, p3:3}, 
];

function projectlogoInit() {

    const logocanvas = document.querySelector('#logoCanvas');
    if(typeof logocanvas === 'undefined' || logocanvas === null) {
        // No logo canvas
        return;
    }
    const WIDTH = logocanvas.width;
    const HEIGHT = logocanvas.height;

    // Set some camera attributes.
    const VIEW_ANGLE = 45;
    const ASPECT = WIDTH / HEIGHT;
    const NEAR = 0.1;
    const FAR = 10000;

    // Create a WebGL renderer, camera
    // and a scene
    projectlogorenderer = new THREE.WebGLRenderer({ alpha: true, canvas: logocanvas });
    projectlogocamera =
        new THREE.PerspectiveCamera(
            VIEW_ANGLE,
            ASPECT,
            NEAR,
            FAR
        );

    projectlogoscene = new THREE.Scene();

    // Add the camera to the scene.
    projectlogoscene.add(projectlogocamera);

    // Start the renderer.
    projectlogorenderer.setSize(WIDTH, HEIGHT);

    // Attach the renderer-supplied
    // DOM element.
    //container.appendChild(projectlogorenderer.domElement);

    // create a point light
    const pointLight =
      new THREE.PointLight(0xFFFFFF);

    // set its position
    pointLight.position.x = 10;
    pointLight.position.y = 50;
    pointLight.position.z = 130;

    // add to the scene
    projectlogoscene.add(pointLight);

    var geom = new THREE.Geometry(); 
    for(var i=0; i<projectlogovertices.length; i++){
        geom.vertices.push(new THREE.Vector3( projectlogovertices[i].x,  projectlogovertices[i].y,  projectlogovertices[i].z));

    }
    
    for(var i=0; i<projectlogosurfaces.length; i++){
        //projectlogosurfaces[i].params.overdraw = false;
        //geom.materials.push(projectlogosurfaces[i].params);
        var color = new THREE.Color( 0xffaa00 );
        geom.faces.push( new THREE.Face3( projectlogosurfaces[i].p1,projectlogosurfaces[i].p2,projectlogosurfaces[i].p3, null, null ,null ));
        geom.faceVertexUvs[0].push([new THREE.Vector2(0, 0),new THREE.Vector2(0, 1),new THREE.Vector2(1, 1)]);
    }


    geom.computeFaceNormals();
    //geom.computeCentroids();
    geom.computeVertexNormals();


    var texture = new THREE.TextureLoader().load( '/pics/cratetexture.gif' );
    var material = new THREE.MeshBasicMaterial( { map: texture } );
    projectlogomesh = new THREE.Mesh( geom, material);
    projectlogomesh.material.side = THREE.DoubleSide;
    projectlogomesh.position.z = -350;
    projectlogoscene.add(projectlogomesh);

    // Schedule the first frame.
    requestAnimationFrame(projectlogoUpdate);
}


function projectlogoUpdate() {
  projectlogomesh.rotation.y += 0.01;
  // Draw!
  projectlogorenderer.render(projectlogoscene, projectlogocamera);
  requestAnimationFrame(projectlogoUpdate);

}

