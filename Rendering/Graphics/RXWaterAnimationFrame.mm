//
//  RXWaterAnimationFrame.m
//  rivenx
//
//  Created by Jean-Francois Roy on 28/03/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXWaterAnimationFrame.h"

#import <dlfcn.h>

#import "RXRendering.h"

#import "llvm/Module.h"
#import "llvm/Constants.h"
#import "llvm/CallingConv.h"
#import "llvm/DerivedTypes.h"
#import "llvm/Instructions.h"
#import "llvm/ExecutionEngine/JIT.h"
#import "llvm/ExecutionEngine/Interpreter.h"
#import "llvm/ExecutionEngine/GenericValue.h"
#import "llvm/Support/LLVMBuilder.h"
#import "llvm/Analysis/Verifier.h"
#import "llvm/Assembly/PrintModulePass.h"
#import "llvm/PassManager.h"

static llvm::Module* s_OpenGLModule;
static llvm::ExecutionEngine* s_EE = 0;

static void _RXRegister_CopyPixels() {
// void (*copy_pixels)(GLIContext ctx, GLint x, GLint y, GLsizei width, GLsizei height, GLenum type);
	std::vector<const llvm::Type*> args;
	
//	args.push_back(llvm::PointerType::getUnqual(llvm::Type::Int8Ty)); // ctx
	args.push_back(llvm::Type::Int32Ty); // x
	args.push_back(llvm::Type::Int32Ty); // y
	args.push_back(llvm::Type::Int32Ty); // width
	args.push_back(llvm::Type::Int32Ty); // height
	args.push_back(llvm::Type::Int32Ty); // type
	
	llvm::FunctionType* ft = llvm::FunctionType::get(llvm::Type::VoidTy, args, false);
	
	// get glCopyPixels
//	CGLContextObj cgl_ctx = [RXGetWorldView() renderContext];
	
	llvm::Function* f = new llvm::Function(ft, llvm::GlobalValue::ExternalLinkage, "glCopyPixels", s_OpenGLModule);
	f->setCallingConv(llvm::CallingConv::C);
	
//	s_EE->addGlobalMapping(f, reinterpret_cast<void*>(cgl_ctx->disp.copy_pixels));
	s_EE->addGlobalMapping(f, reinterpret_cast<void*>(dlsym(RTLD_DEFAULT, "glCopyPixels")));
}

static void _RXRegister_RasterPos2i() {
// 	void (*raster_pos2i)(GLIContext ctx, GLint x, GLint y);
	std::vector<const llvm::Type*> args;
	
//	args.push_back(llvm::PointerType::getUnqual(llvm::Type::Int8Ty)); // ctx
	args.push_back(llvm::Type::Int32Ty); // x
	args.push_back(llvm::Type::Int32Ty); // y
	
	llvm::FunctionType* ft = llvm::FunctionType::get(llvm::Type::VoidTy, args, false);
	
	// get glCopyPixels
//	CGLContextObj cgl_ctx = [RXGetWorldView() renderContext];
	
	llvm::Function* f = new llvm::Function(ft, llvm::GlobalValue::ExternalLinkage, "glRasterPos2i", s_OpenGLModule);
	f->setCallingConv(llvm::CallingConv::C);
	
//	s_EE->addGlobalMapping(f, reinterpret_cast<void*>(cgl_ctx->disp.raster_pos2i));
	s_EE->addGlobalMapping(f, reinterpret_cast<void*>(dlsym(RTLD_DEFAULT, "glRasterPos2i")));
}

static void _RXRegisterGLGlobals(void) {
	_RXRegister_CopyPixels();
	_RXRegister_RasterPos2i();
}

@implementation RXWaterAnimationFrame

+ (void)initialize {
	if (self == [RXWaterAnimationFrame class]) {
		s_OpenGLModule = new llvm::Module("OpenGL");
		llvm::ExistingModuleProvider* MP = new llvm::ExistingModuleProvider(s_OpenGLModule);
		
		s_EE = llvm::ExecutionEngine::create(MP, false);
		
		_RXRegisterGLGlobals();
		
//		verifyModule(*s_OpenGLModule, llvm::PrintMessageAction);

//		llvm::PassManager PM;
//		PM.add(new llvm::PrintModulePass(&llvm::cout));
//		PM.run(*s_OpenGLModule);
	}
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithSFXEProgram:(uint16_t*)sfxeProgram roi:(NSRect)roi {
	self = [super init];
	if (!self) return nil;
	
	llvm::Function* glCopyPixels_f = llvm::cast<llvm::Function>(s_OpenGLModule->getFunction("glCopyPixels"));
	assert(glCopyPixels_f);
	llvm::Function* glRasterPos2i_f = llvm::cast<llvm::Function>(s_OpenGLModule->getFunction("glRasterPos2i"));
	assert(glRasterPos2i_f);
	
	llvm::Module* M = new llvm::Module("");
	_MP = new llvm::ExistingModuleProvider(M);
	
	// void (*)(GLIContext ctx)
	std::vector<const llvm::Type*> args;
//	args.push_back(llvm::PointerType::getUnqual(llvm::Type::Int8Ty)); // ctx
	llvm::FunctionType* ft = llvm::FunctionType::get(llvm::Type::VoidTy, args, false);
	
	_f = new llvm::Function(ft, llvm::GlobalValue::ExternalLinkage, "", M);
//	llvm::Function::arg_iterator argIter = _f->arg_begin();
//	llvm::Value* ctx = argIter;
	
	llvm::BasicBlock* block = new llvm::BasicBlock("entry", _f);
	llvm::LLVMBuilder builder(block);
	
	uint32_t dy = roi.origin.y + roi.size.height;
	uint16_t command = CFSwapInt16BigToHost(*sfxeProgram);
	while (command != 4) {
		if (command == 1) dy--;
		else if (command == 3) {
			uint32_t dx = CFSwapInt16BigToHost(*(sfxeProgram + 1));
			uint32_t sx = CFSwapInt16BigToHost(*(sfxeProgram + 2));
			uint32_t sy = kRXCardViewportSize.height - CFSwapInt16BigToHost(*(sfxeProgram + 3));
			uint32_t rows = CFSwapInt16BigToHost(*(sfxeProgram + 4));
			sfxeProgram += 4;
			
			// glRasterPos2i(ctx, dx, dy)
			std::vector<llvm::Value*> rasterPosArgs;
//			rasterPosArgs.push_back(ctx);
			rasterPosArgs.push_back(llvm::ConstantInt::get(llvm::Type::Int32Ty, dx));
			rasterPosArgs.push_back(llvm::ConstantInt::get(llvm::Type::Int32Ty, dy));
			builder.CreateCall(glRasterPos2i_f, rasterPosArgs.begin(), rasterPosArgs.end());
			
			// glCopyPixels(sx, sy, rows, 1, GL_COLOR)
			std::vector<llvm::Value*> copyPixelsArgs;
//			copyPixelsArgs.push_back(ctx);
			copyPixelsArgs.push_back(llvm::ConstantInt::get(llvm::Type::Int32Ty, sx));
			copyPixelsArgs.push_back(llvm::ConstantInt::get(llvm::Type::Int32Ty, sy));
			copyPixelsArgs.push_back(llvm::ConstantInt::get(llvm::Type::Int32Ty, rows));
			copyPixelsArgs.push_back(llvm::ConstantInt::get(llvm::Type::Int32Ty, 1));
			copyPixelsArgs.push_back(llvm::ConstantInt::get(llvm::Type::Int32Ty, GL_COLOR));
			builder.CreateCall(glCopyPixels_f, copyPixelsArgs.begin(), copyPixelsArgs.end());
		} else abort();
		
		sfxeProgram++;
		command = CFSwapInt16BigToHost(*sfxeProgram);
	}
	
	builder.CreateRetVoid();
	
	s_EE->addModuleProvider(_MP);
	
//	verifyModule(*M, llvm::PrintMessageAction);

//	llvm::PassManager PM;
//	PM.add(new llvm::PrintModulePass(&llvm::cout));
//	PM.run(*M);
			
	return self;
}

- (void)dealloc {
	llvm::Module* M = s_EE->removeModuleProvider(_MP);
	delete _MP;
	delete M;
	
	[super dealloc];
}

- (void)renderInContext:(CGLContextObj)cgl_ctx {
	std::vector<llvm::GenericValue> args;
//	args.push_back(llvm::GenericValue(&(cgl_ctx->rend)));
	s_EE->runFunction(_f, args);
}

@end
