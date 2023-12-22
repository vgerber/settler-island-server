use proc_macro::TokenStream;
use quote::quote;

#[proc_macro_derive(HasStateId)]
pub fn has_state_id_derive(input: TokenStream) -> TokenStream {
    let ast = syn::parse(input).unwrap();
    impl_state_id(&ast)
}

fn impl_state_id(ast: &syn::DeriveInput) -> TokenStream {
    let name = &ast.ident;
    let gen = quote! {
        use settler_island_util::state_id::{HasStateId, StateId};
        impl HasStateId for #name {
            fn get_id(&self) -> StateId {
                stringify!(#name)
            }
        }

        impl #name {
            pub fn get_id() -> StateId {
                stringify!(#name)
            }
        }
    };
    gen.into()
}
