/*
 * Copyright (C) 2018 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "ViewController.h"
#import "FilamentView.h"
#import <filament/Engine.h>
#import <filament/Renderer.h>
#import <filament/Scene.h>
#import <filament/View.h>
#import <filament/RenderableManager.h>
#import <filament/TransformManager.h>

using namespace filament;
using utils::Entity;
using utils::EntityManager;

struct App {
    VertexBuffer* vb;
    IndexBuffer* ib;
    Material* mat;
    Entity renderable;
};

struct Vertex {
    filament::math::float2 position;
    uint32_t color;
};

static const Vertex TRIANGLE_VERTICES[3] = {
    {{1, 0}, 0xffff0000u},
    {{cos(M_PI * 2 / 3), sin(M_PI * 2 / 3)}, 0xff00ff00u},
    {{cos(M_PI * 4 / 3), sin(M_PI * 4 / 3)}, 0xff0000ffu},
};

static constexpr uint16_t TRIANGLE_INDICES[3] = { 0, 1, 2 };

// This file is compiled via the matc tool. See the "Run Script" build phase.
static constexpr uint8_t BAKED_COLOR_PACKAGE[] = {
#include "bakedColor.inc"
};

struct PlatformView{
    View* filaView;
    Camera* camera;
    SwapChain* swapChain;
    FilamentView *iosView;
    
    void destroy(Engine* engine){
        engine->destroy(filaView);
        engine->destroy(camera);
        engine->destroy(swapChain);
    };
    
    void create(Engine* engine, FilamentView *iosView_){
        iosView = iosView_;
        swapChain = engine->createSwapChain((__bridge void*) iosView.layer);
        camera = engine->createCamera();

        filaView = engine->createView();
        filaView->setPostProcessingEnabled(true);
        filaView->setDepthPrepass(filament::View::DepthPrepass::DISABLED);
        
        filaView->setCamera(camera);
        
        filaView->setViewport(Viewport(0, 0, UIScreen.mainScreen.nativeScale * iosView.bounds.size.width, UIScreen.mainScreen.nativeScale * iosView.bounds.size.height));
    };
    
    void setClearColor(math::float4 color){
        filaView->setClearColor(color);
    }
    
    void setScene(Scene* scene_){
        filaView->setScene(scene_);
    }
    
    void render(Renderer* renderer){
        constexpr float ZOOM = 1.5f;
        const uint32_t w = filaView->getViewport().width;
        const uint32_t h = filaView->getViewport().height;
        const float aspect = (float) w / h;
        camera->setProjection(Camera::Projection::ORTHO,
                              -aspect * ZOOM, aspect * ZOOM,
                              -ZOOM, ZOOM, 0, 1);
        
        if (renderer->beginFrame(swapChain)) {
            renderer->render(filaView);
            renderer->endFrame();
        }
    }
};

@interface ViewController (){
    Engine* engine;
    Renderer* renderer;
    Scene* scene;
    PlatformView view[2];
    App app;
    CADisplayLink* displayLink;

    // The amount of rotation to apply to the camera to offset the device's rotation (in radians)
    float deviceRotation;
    float desiredRotation;
}

@property (weak, nonatomic) IBOutlet FilamentView *view1;
@property (weak, nonatomic) IBOutlet FilamentView *view2;

@end

@implementation ViewController

- (void) viewDidLoad{
    [super viewDidLoad];

    [self initializeFilament];

    // Call renderloop 60 times a second.
    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderloop)];
    displayLink.preferredFramesPerSecond = 60;
    [displayLink addToRunLoop:NSRunLoop.currentRunLoop forMode:NSDefaultRunLoopMode];

    // Call didRotate when the device orientation changes.
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didRotate:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
}


- (void)dealloc
{
    engine->destroy(renderer);
    engine->destroy(scene);
    view[0].destroy(engine);
    view[1].destroy(engine);
    engine->destroy(&engine);
}

- (BOOL)shouldAutorotate
{
    return NO;
}


- (void)initializeFilament
{
    engine = Engine::create(filament::Engine::Backend::METAL);

    view[0].create(engine, self.view1);
    view[1].create(engine, self.view2);
    
    view[0].setClearColor({0.1, 0.125, 0.25, 1.0});
    view[1].setClearColor({0.1, 0.25, 0.125, 1.0});
    
    renderer = engine->createRenderer();
    scene = engine->createScene();

    app.vb = VertexBuffer::Builder()
        .vertexCount(3)
        .bufferCount(1)
        .attribute(VertexAttribute::POSITION, 0, VertexBuffer::AttributeType::FLOAT2, 0, 12)
        .attribute(VertexAttribute::COLOR, 0, VertexBuffer::AttributeType::UBYTE4, 8, 12)
        .normalized(VertexAttribute::COLOR)
        .build(*engine);
    app.vb->setBufferAt(*engine, 0,
                        VertexBuffer::BufferDescriptor(TRIANGLE_VERTICES, 36, nullptr));

    app.ib = IndexBuffer::Builder()
        .indexCount(3)
        .bufferType(IndexBuffer::IndexType::USHORT)
        .build(*engine);
    app.ib->setBuffer(*engine,
                      IndexBuffer::BufferDescriptor(TRIANGLE_INDICES, 6, nullptr));

    app.mat = Material::Builder()
        .package((void*) BAKED_COLOR_PACKAGE, sizeof(BAKED_COLOR_PACKAGE))
        .build(*engine);

    app.renderable = EntityManager::get().create();
    RenderableManager::Builder(1)
        .boundingBox({{ -1, -1, -1 }, { 1, 1, 1 }})
        .material(0, app.mat->getDefaultInstance())
        .geometry(0, RenderableManager::PrimitiveType::TRIANGLES, app.vb, app.ib, 0, 3)
        .culling(false)
        .receiveShadows(false)
        .castShadows(false)
        .build(*engine, app.renderable);
    scene->addEntity(app.renderable);
    
    view[0].setScene(scene);
    view[1].setScene(scene);
}

- (void)renderloop
{
    [self update];
    view[0].render(self->renderer);
    view[1].render(self->renderer);
}

- (void)update
{
    auto& tcm = engine->getTransformManager();

    [self updateRotation];

    tcm.setTransform(tcm.getInstance(app.renderable),
                     filament::math::mat4f::rotation(CACurrentMediaTime(), filament::math::float3{0, 0, 1}) *
                     filament::math::mat4f::rotation(deviceRotation, filament::math::float3{0, 0, 1}));
}

- (void)didRotate:(NSNotification*)notification
{
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    desiredRotation = [self rotationForDeviceOrientation:orientation];
}

- (void)updateRotation
{
    static const float ROTATION_SPEED = 0.1;
    float diff = abs(desiredRotation - deviceRotation);
    if (diff > FLT_EPSILON) {
        if (desiredRotation > deviceRotation) {
            deviceRotation += fmin(ROTATION_SPEED, diff);
        }
        if (desiredRotation < deviceRotation) {
            deviceRotation -= fmin(ROTATION_SPEED, diff);
        }
    }
}

- (float)rotationForDeviceOrientation:(UIDeviceOrientation)orientation
{
    switch (orientation) {
        default:
        case UIDeviceOrientationPortrait:
            return 0.0f;

        case UIDeviceOrientationLandscapeRight:
            return M_PI_2;

        case UIDeviceOrientationLandscapeLeft:
            return -M_PI_2;

        case UIDeviceOrientationPortraitUpsideDown:
            return M_PI;
    }
}



@end
