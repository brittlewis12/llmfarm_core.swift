//
//  LLaMa.swift
//  Created by Guinmoon.

import Foundation
import llmfarm_core_cpp

public class LLaMa: LLMBase {
    
    public var model: OpaquePointer?
    public var hardware_arch: String=""
    
    public override func llm_load_model(path: String = "", contextParams: ModelAndContextParams = .default, params:gpt_context_params ) throws -> Bool{
        var context_params = llama_context_default_params()
        var model_params = llama_model_default_params()
        context_params.n_ctx = UInt32(contextParams.context)
        context_params.seed = UInt32(contextParams.seed)
        context_params.f16_kv = contextParams.f16Kv
        context_params.n_threads = UInt32(contextParams.n_threads)
        context_params.logits_all = contextParams.logitsAll
//        context_params.n_batch = contextParams.
        model_params.vocab_only = contextParams.vocabOnly
        model_params.use_mlock = contextParams.useMlock
        model_params.use_mmap = contextParams.useMMap
        var progress_callback_user_data:Int32 = 0
//        model_params.progress_callback_user_data = progress_callback_user_data
//        context_params.rope_freq_base = 10000.0
//        context_params.rope_freq_scale = 1
        
        if contextParams.use_metal{
            model_params.n_gpu_layers = 1
        }else{
            model_params.n_gpu_layers = 0
        }
        self.hardware_arch = Get_Machine_Hardware_Name()// Disable Metal on intel Mac
        if self.hardware_arch=="x86_64"{
            model_params.n_gpu_layers = 0
        }
        
        if contextParams.lora_adapters.count>0{
            model_params.use_mmap = false
        }
                        
        self.model = llama_load_model_from_file(path, model_params)
        if self.model == nil{
            return false
        }
        
        for lora in contextParams.lora_adapters{            
            llama_model_apply_lora_from_file(model,lora.0,lora.1,nil,6);
        }
        
        self.context = llama_new_context_with_model(self.model, context_params)
        if self.context == nil {
            return false
        }
//        var tokens_tmp: [llama_token] = [Int32](repeating: 0, count: 100000)
//        var tokens_count:Int = 0
//        llama_load_session_file(self.context,"/Users/guinmoon/Library/Containers/com.guinmoon.LLMFarm/Data/Documents/models/dump_state.bin",tokens_tmp.mutPtr, 100000,&tokens_count)
//        self.session_tokens.append(contentsOf: tokens_tmp[0..<tokens_count])
//        try? llm_eval(inputBatch:self.session_tokens)
//        llama_load_state(self.context,"/Users/guinmoon/Library/Containers/com.guinmoon.LLMFarm/Data/Documents/models/dump_state_.bin")

        return true
    }

    public override func reset_context(newParams: ModelAndContextParams = .default) throws -> Bool {
        if self.model == nil {
            return false
        }

        if self.context != nil {
            llama_free(self.context)
        }

        var context_params = llama_context_default_params()
        context_params.n_ctx = UInt32(newParams.context)
        context_params.seed = UInt32(newParams.seed)
        context_params.f16_kv = newParams.f16Kv
        context_params.n_threads = UInt32(newParams.n_threads)
        context_params.logits_all = newParams.logitsAll

        self.past = []
        self.nPast = 0
        self.session_tokens = []
        self.context = llama_new_context_with_model(self.model, context_params)

        if self.context == nil {
            return false
        }

        _ = try self.llm_init_logits()

        return true
    }

    public override func load_past(_ history: String) -> Bool {
        let tokens = llm_tokenize(history)
        self.session_tokens.append(contentsOf: tokens[0..<tokens.count])
        self.past.append(contentsOf: [tokens])
        let batchSize = 256
        let batches = (tokens.count + batchSize - 1) / batchSize
        var ok = true
        print("loading \(tokens.count) past tokens in \(batches) batches of \(batchSize)")
        for batchNum in 0..<batches {
            let startIndex = batchNum * batchSize
            let endIndex = min(startIndex + batchSize, tokens.count)
            let batch = Array(tokens[startIndex..<endIndex])
            ok = (try? llm_eval(inputBatch: batch)) ?? false
            if !ok { break }
            // NOTE: must set nPast _after_ evaling tokens, not before, to ensure correct offsets to next kv access
            self.nPast = batchNum == 0 ? Int32(batch.count) : nPast + Int32(batch.count)
            print("loaded batch \(batchNum + 1) of \(batches)")
        }

        if ok {
            print("loaded \(tokens.count) past tokens")
        } else {
            print("something went wrong loading past, resetting")
            self.session_tokens = []
            self.past = []
            self.nPast = 0
        }

        return ok
    }

    deinit {
//        llama_save_state(self.context,"/Users/guinmoon/Library/Containers/com.guinmoon.LLMFarm/Data/Documents/models/dump_state_.bin")
//        llama_save_session_file(self.context,"/Users/guinmoon/Library/Containers/com.guinmoon.LLMFarm/Data/Documents/models/dump_state.bin",self.session_tokens, self.session_tokens.count)
        llama_free(context)
        llama_free_model(model)
    }
    
    override func llm_get_n_ctx(ctx: OpaquePointer!) -> Int32{
        return llama_n_ctx(self.context)
    }
    
    override func llm_n_vocab(_ ctx: OpaquePointer!) -> Int32{
        return llama_n_vocab(self.model)
    }
    
    override func llm_get_logits(_ ctx: OpaquePointer!) -> UnsafeMutablePointer<Float>?{
        return llama_get_logits(self.context);
    }

    public override func llm_eval(inputBatch:[ModelToken]) throws -> Bool{
        var mutable_inputBatch = inputBatch
        if llama_eval(self.context, mutable_inputBatch.mutPtr, Int32(inputBatch.count), min(self.contextParams.context, self.nPast)) != 0 {
            return false
        }
        return true
    }
    
    public override func llm_token_to_str(outputToken:Int32) -> String? {
        if let cStr = llama_token_to_str(context, outputToken){
//            print(String(cString: cStr))
            return String(cString: cStr)
        }
        return nil
    }
    
    public override func llm_token_nl() -> ModelToken{
        return llama_token_nl(self.context)
    }

    public override func llm_token_bos() -> ModelToken{
       return llama_token_bos(self.context)
    }
    
    public override func llm_token_eos() -> ModelToken{
        return llama_token_eos(self.context)
    }
    

    
    
    public override func llm_tokenize(_ input: String) -> [ModelToken] {
        if input.count == 0 {
            return []
        }

//        llama_tokenize(
//                struct llama_context * ctx,
//                          const char * text,
//                                 int   text_len,
//                         llama_token * tokens,
//                                 int   n_max_tokens,
//                                bool   add_bos)
        let n_tokens = Int32(input.utf8.count) + (self.contextParams.add_bos_token == true ? 1 : 0)
        var embeddings: [llama_token] = Array<llama_token>(repeating: llama_token(), count: input.utf8.count)
        let n = llama_tokenize(self.model, input, Int32(input.utf8.count), &embeddings, n_tokens, self.contextParams.add_bos_token, self.contextParams.parse_special_tokens)
        if n<=0{
            return []
        }
        if Int(n) <= embeddings.count {
            embeddings.removeSubrange(Int(n)..<embeddings.count)
        }
        
        if self.contextParams.add_eos_token {
            embeddings.append(llama_token_eos(self.context))
        }
        
        return embeddings
    }
}

